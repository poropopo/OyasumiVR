# CefSharp Subprocess Leak Test Script (Improved)
# リリースモードでの実行と、より長い待機時間で確実に再現

param(
    [string]$ExePath = ".\src-overlay-sidecar\bin\Debug\net8.0-windows\win-x64\oyasumivr-overlay-sidecar.exe",
    [int]$WaitSeconds = 10,
    [int]$TestIterations = 1,
    [switch]$CleanupOnly,
    [switch]$UseReleaseMode
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
        Start-Sleep -Seconds 2
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

# ダミーの親プロセスを作成（リリースモード用）
function Start-DummyParentProcess {
    # エンコードされたコマンドを使用してPowerShell変数の展開問題を回避
    $scriptBlock = {
        Write-Host "Dummy parent process started (PID: $PID)"
        Write-Host "Press Ctrl+C to stop"
        while ($true) {
            Start-Sleep -Seconds 1
        }
    }

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock.ToString()))

    $process = Start-Process powershell -ArgumentList "-NoExit", "-EncodedCommand", $encodedCommand -PassThru -WindowStyle Minimized
    Start-Sleep -Seconds 2
    return $process
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
    $dummyParent = $null
    $processArgs = @()

    if ($UseReleaseMode) {
        Write-Info "[ステップ 3] リリースモードで起動（ダミー親プロセス使用）"
        $dummyParent = Start-DummyParentProcess
        Write-Success "ダミー親プロセス起動 (PID: $($dummyParent.Id))"

        # リリースモード: <grpc port> <parent pid>
        $processArgs = @("50051", "$($dummyParent.Id)")
        Write-Info "起動引数: oyasumivr-overlay-sidecar.exe $($processArgs -join ' ')"
    }
    else {
        Write-Info "[ステップ 3] devモードで起動"
        $processArgs = @("dev")
        Write-Warning "注意: devモードではEnvironment.Exit()のコードパスが実行されません"
        Write-Warning "より確実なテストには -UseReleaseMode を使用してください"
    }

    try {
        $process = Start-Process -FilePath $fullPath -ArgumentList $processArgs -PassThru -WindowStyle Hidden
        Write-Success "プロセス起動成功 (PID: $($process.Id))"
    }
    catch {
        Write-Error "プロセス起動失敗: $_"
        if ($dummyParent) { Stop-Process -Id $dummyParent.Id -Force }
        return $false
    }
    Write-Host ""

    # 4. 待機（CefSharpの初期化とブラウザインスタンスの作成を待つ）
    Write-Info "[ステップ 4] CefSharp初期化とブラウザ作成を待機中 ($WaitSeconds 秒)"
    Write-Info "この間にCefSharpが完全に初期化され、ブラウザインスタンスが作成されます"
    for ($i = $WaitSeconds; $i -gt 0; $i--) {
        Write-Host "  残り $i 秒..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    Write-Host "  完了                "

    # 4.5. 起動後のプロセス確認
    $beforeCount = Get-CefSharpSubprocessCount
    Write-Info "起動後のCefSharpサブプロセス数: $beforeCount"

    if ($beforeCount -eq 0) {
        Write-Warning "警告: CefSharpサブプロセスが検出されませんでした"
        Write-Warning "CefSharpが正しく初期化されていない可能性があります"
        Write-Warning "待機時間を増やすか、ログを確認してください"
    }
    Write-Host ""

    # 5. プロセスの強制終了
    Write-Info "[ステップ 5] プロセスを強制終了（Cef.Shutdown()を呼ばせない）"
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        Write-Warning "メインプロセスを強制終了しました (PID: $($process.Id))"
    }
    catch {
        Write-Error "プロセス終了失敗: $_"
        if ($dummyParent) { Stop-Process -Id $dummyParent.Id -Force }
        return $false
    }

    # ダミー親プロセスもクリーンアップ
    if ($dummyParent) {
        Stop-Process -Id $dummyParent.Id -Force -ErrorAction SilentlyContinue
        Write-Info "ダミー親プロセスを終了しました"
    }
    Write-Host ""

    # 6. 少し待機（プロセスが完全に終了するまで）
    Write-Info "[ステップ 6] プロセス終了を待機中 (3秒)"
    Start-Sleep -Seconds 3
    Write-Host ""

    # 7. サブプロセスのチェック
    Write-Info "[ステップ 7] CefSharpサブプロセスをチェック"
    $leakedCount = Show-CefSharpSubprocesses
    Write-Host ""

    # 8. 結果判定
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "テスト結果 #$Iteration" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    if ($beforeCount -eq 0) {
        Write-Warning "結果: 不明（CefSharpサブプロセスが起動していませんでした）"
        Write-Info "待機時間を増やすか、アプリケーションのログを確認してください"
        return $null
    }
    elseif ($leakedCount -gt 0) {
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
║   CefSharp Subprocess Leak Test (Improved)           ║
║   OyasumiVR Overlay Sidecar                          ║
╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Info "設定:"
Write-Host "  実行ファイル: $ExePath"
Write-Host "  待機時間: $WaitSeconds 秒"
Write-Host "  テスト回数: $TestIterations"
Write-Host "  リリースモード: $(if ($UseReleaseMode) { 'はい' } else { 'いいえ (devモード)' })"
Write-Host ""

if (-not $UseReleaseMode) {
    Write-Warning "═══════════════════════════════════════════════════════"
    Write-Warning "注意: devモードで実行しています"
    Write-Warning "より確実なテストには -UseReleaseMode を指定してください"
    Write-Warning "═══════════════════════════════════════════════════════"
    Write-Host ""
}

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
$unknownCount = 0

for ($i = 1; $i -le $TestIterations; $i++) {
    $result = Test-SubprocessLeak -Iteration $i

    if ($result -eq $true) {
        $successCount++
    }
    elseif ($result -eq $false) {
        $failCount++
    }
    else {
        $unknownCount++
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
if ($unknownCount -gt 0) {
    Write-Warning "不明: $unknownCount"
}
Write-Host ""

if ($failCount -gt 0) {
    Write-Error "サブプロセスリークが検出されました！"
    Write-Warning "修正が必要です。"
    exit 1
}
elseif ($unknownCount -gt 0) {
    Write-Warning "テスト結果が不明です。待機時間を増やしてください。"
    exit 2
}
else {
    Write-Success "すべてのテストが成功しました！"
    exit 0
}
