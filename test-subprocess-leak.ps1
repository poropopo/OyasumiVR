# CefSharp Subprocess Leak Test Script
# このスクリプトはoyasumivr-overlay-sidecar.exeを起動し、強制終了後にサブプロセスが残るかをテストします

param(
    [string]$ExePath = ".\src-overlay-sidecar\bin\Debug\net8.0-windows\oyasumivr-overlay-sidecar.exe",
    [int]$WaitSeconds = 5,
    [int]$TestIterations = 1,
    [switch]$CleanupOnly
)

# 色付き出力用の関数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-ColorOutput "✓ $Message" "Green" }
function Write-Error { param([string]$Message) Write-ColorOutput "✗ $Message" "Red" }
function Write-Warning { param([string]$Message) Write-ColorOutput "⚠ $Message" "Yellow" }
function Write-Info { param([string]$Message) Write-ColorOutput "ℹ $Message" "Cyan" }

# CefSharpサブプロセスをすべてクリーンアップ
function Cleanup-CefSharpProcesses {
    Write-Info "CefSharpサブプロセスをクリーンアップ中..."

    $cefProcesses = Get-Process | Where-Object { $_.ProcessName -like "*CefSharp*" -or $_.ProcessName -like "*cefsharp*" }

    if ($cefProcesses) {
        foreach ($proc in $cefProcesses) {
            try {
                Write-Warning "  プロセスを終了: $($proc.ProcessName) (PID: $($proc.Id))"
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Error "  プロセス終了失敗: $($proc.ProcessName) (PID: $($proc.Id))"
            }
        }
        Start-Sleep -Seconds 1
    }
    else {
        Write-Success "CefSharpサブプロセスは見つかりませんでした"
    }
}

# オーバーレイサイドカープロセスをクリーンアップ
function Cleanup-SidecarProcesses {
    Write-Info "オーバーレイサイドカープロセスをクリーンアップ中..."

    $sidecarProcesses = Get-Process | Where-Object { $_.ProcessName -like "*oyasumivr-overlay-sidecar*" }

    if ($sidecarProcesses) {
        foreach ($proc in $sidecarProcesses) {
            try {
                Write-Warning "  プロセスを終了: $($proc.ProcessName) (PID: $($proc.Id))"
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Error "  プロセス終了失敗: $($proc.ProcessName) (PID: $($proc.Id))"
            }
        }
        Start-Sleep -Seconds 1
    }
    else {
        Write-Success "オーバーレイサイドカープロセスは見つかりませんでした"
    }
}

# サブプロセスの数を取得
function Get-CefSharpSubprocessCount {
    $processes = Get-Process | Where-Object {
        $_.ProcessName -like "*CefSharp.BrowserSubprocess*" -or
        $_.ProcessName -like "*cefsharp.browsersubprocess*"
    }
    return $processes.Count
}

# サブプロセスの詳細を表示
function Show-CefSharpSubprocesses {
    $processes = Get-Process | Where-Object {
        $_.ProcessName -like "*CefSharp*" -or
        $_.ProcessName -like "*cefsharp*"
    }

    if ($processes) {
        Write-Warning "検出されたCefSharpプロセス:"
        foreach ($proc in $processes) {
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-Host "  - $($proc.ProcessName) (PID: $($proc.Id), Memory: $memoryMB MB)" -ForegroundColor Yellow
        }
        return $processes.Count
    }
    else {
        Write-Success "CefSharpプロセスは見つかりませんでした"
        return 0
    }
}

# メイン処理
function Test-SubprocessLeak {
    param([int]$Iteration)

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "テスト実行 #$Iteration" -ForegroundColor Magenta
    Write-Host "========================================`n" -ForegroundColor Magenta

    # 1. 初期クリーンアップ
    Write-Info "[ステップ 1] 既存プロセスのクリーンアップ"
    Cleanup-SidecarProcesses
    Cleanup-CefSharpProcesses
    Write-Host ""

    # 2. 実行ファイルの存在確認
    Write-Info "[ステップ 2] 実行ファイルの確認"
    if (-not (Test-Path $ExePath)) {
        Write-Error "実行ファイルが見つかりません: $ExePath"
        return $false
    }
    $fullPath = Resolve-Path $ExePath
    Write-Success "実行ファイル: $fullPath"
    Write-Host ""

    # 3. プロセス起動
    Write-Info "[ステップ 3] oyasumivr-overlay-sidecar.exe を起動"
    try {
        $process = Start-Process -FilePath $fullPath -ArgumentList "dev" -PassThru -WindowStyle Hidden
        Write-Success "プロセス起動成功 (PID: $($process.Id))"
    }
    catch {
        Write-Error "プロセス起動失敗: $_"
        return $false
    }
    Write-Host ""

    # 4. 待機（CefSharpの初期化を待つ）
    Write-Info "[ステップ 4] CefSharpの初期化を待機中 ($WaitSeconds 秒)"
    for ($i = $WaitSeconds; $i -gt 0; $i--) {
        Write-Host "  残り $i 秒..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    Write-Host "  完了                "

    # 4.5. 起動後のプロセス確認
    $beforeCount = Get-CefSharpSubprocessCount
    Write-Info "起動後のCefSharpサブプロセス数: $beforeCount"
    Write-Host ""

    # 5. プロセスの強制終了
    Write-Info "[ステップ 5] プロセスを強制終了"
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        Write-Warning "メインプロセスを強制終了しました (PID: $($process.Id))"
    }
    catch {
        Write-Error "プロセス終了失敗: $_"
        return $false
    }
    Write-Host ""

    # 6. 少し待機（プロセスが完全に終了するまで）
    Write-Info "[ステップ 6] プロセス終了を待機中 (2秒)"
    Start-Sleep -Seconds 2
    Write-Host ""

    # 7. サブプロセスのチェック
    Write-Info "[ステップ 7] CefSharpサブプロセスをチェック"
    $leakedCount = Show-CefSharpSubprocesses
    Write-Host ""

    # 8. 結果判定
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "テスト結果 #$Iteration" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    if ($leakedCount -gt 0) {
        Write-Error "失敗: $leakedCount 個のCefSharpサブプロセスが残っています"
        Write-Warning "これはメモリリーク/プロセスリークの証拠です"
        return $false
    }
    else {
        Write-Success "成功: サブプロセスは適切にクリーンアップされました"
        return $true
    }
}

# スクリプト実行開始
Write-Host @"

╔═══════════════════════════════════════════════════════╗
║   CefSharp Subprocess Leak Test                      ║
║   OyasumiVR Overlay Sidecar                          ║
╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Info "設定:"
Write-Host "  実行ファイル: $ExePath"
Write-Host "  待機時間: $WaitSeconds 秒"
Write-Host "  テスト回数: $TestIterations"
Write-Host ""

# クリーンアップのみモード
if ($CleanupOnly) {
    Write-Warning "クリーンアップモードで実行中..."
    Cleanup-SidecarProcesses
    Cleanup-CefSharpProcesses
    Write-Success "クリーンアップ完了"
    exit 0
}

# テスト実行
$successCount = 0
$failCount = 0

for ($i = 1; $i -le $TestIterations; $i++) {
    $result = Test-SubprocessLeak -Iteration $i

    if ($result) {
        $successCount++
    }
    else {
        $failCount++
    }

    if ($i -lt $TestIterations) {
        Write-Host "`n次のテストまで3秒待機..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
}

# 最終結果
Write-Host "`n`n" -NoNewline
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   最終結果                                            ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "総テスト数: $TestIterations" -ForegroundColor White
Write-Success "成功: $successCount"
Write-Error "失敗: $failCount"
Write-Host ""

if ($failCount -gt 0) {
    Write-Error "サブプロセスリークが検出されました！"
    Write-Warning "修正が必要です。"
    exit 1
}
else {
    Write-Success "すべてのテストが成功しました！"
    exit 0
}
