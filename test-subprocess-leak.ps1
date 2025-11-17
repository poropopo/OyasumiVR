# CefSharp Subprocess Leak Test Script
# This script launches oyasumivr-overlay-sidecar.exe and checks whether any subprocesses remain after a forced termination.

param(
    [string]$ExePath = ".\src-overlay-sidecar\bin\Debug\net8.0-windows\oyasumivr-overlay-sidecar.exe",
    [int]$WaitSeconds = 5,
    [int]$TestIterations = 1,
    [switch]$CleanupOnly
)

# Helper for colored output
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

# Clean up all CefSharp subprocesses
function Cleanup-CefSharpProcesses {
    Write-Info "Cleaning up CefSharp subprocesses..."

    $cefProcesses = Get-Process | Where-Object { $_.ProcessName -like "*CefSharp*" -or $_.ProcessName -like "*cefsharp*" }

    if ($cefProcesses) {
        foreach ($proc in $cefProcesses) {
            try {
                Write-Warning "  Terminating process: $($proc.ProcessName) (PID: $($proc.Id))"
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Error "  Failed to terminate process: $($proc.ProcessName) (PID: $($proc.Id))"
            }
        }
        Start-Sleep -Seconds 1
    }
    else {
        Write-Success "No CefSharp subprocesses were found"
    }
}

# Clean up overlay sidecar processes
function Cleanup-SidecarProcesses {
    Write-Info "Cleaning up overlay sidecar processes..."

    $sidecarProcesses = Get-Process | Where-Object { $_.ProcessName -like "*oyasumivr-overlay-sidecar*" }

    if ($sidecarProcesses) {
        foreach ($proc in $sidecarProcesses) {
            try {
                Write-Warning "  Terminating process: $($proc.ProcessName) (PID: $($proc.Id))"
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Error "  Failed to terminate process: $($proc.ProcessName) (PID: $($proc.Id))"
            }
        }
        Start-Sleep -Seconds 1
    }
    else {
        Write-Success "No overlay sidecar processes were found"
    }
}

# Get the number of subprocesses
function Get-CefSharpSubprocessCount {
    $processes = Get-Process | Where-Object {
        $_.ProcessName -like "*CefSharp.BrowserSubprocess*" -or
        $_.ProcessName -like "*cefsharp.browsersubprocess*"
    }
    return $processes.Count
}

# Display subprocess details
function Show-CefSharpSubprocesses {
    $processes = Get-Process | Where-Object {
        $_.ProcessName -like "*CefSharp*" -or
        $_.ProcessName -like "*cefsharp*"
    }

    if ($processes) {
        Write-Warning "Detected CefSharp processes:"
        foreach ($proc in $processes) {
            $memoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-Host "  - $($proc.ProcessName) (PID: $($proc.Id), Memory: $memoryMB MB)" -ForegroundColor Yellow
        }
        return $processes.Count
    }
    else {
        Write-Success "No CefSharp processes were found"
        return 0
    }
}

# Main processing
function Test-SubprocessLeak {
    param([int]$Iteration)

    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "Test Run #$Iteration" -ForegroundColor Magenta
    Write-Host "========================================`n" -ForegroundColor Magenta

    # 1. Initial cleanup
    Write-Info "[Step 1] Cleaning up existing processes"
    Cleanup-SidecarProcesses
    Cleanup-CefSharpProcesses
    Write-Host ""

    # 2. Verify executable
    Write-Info "[Step 2] Validating executable"
    if (-not (Test-Path $ExePath)) {
        Write-Error "Executable not found: $ExePath"
        return $false
    }
    $fullPath = Resolve-Path $ExePath
    Write-Success "Executable: $fullPath"
    Write-Host ""

    # 3. Launch process
    Write-Info "[Step 3] Launching oyasumivr-overlay-sidecar.exe"
    try {
        $process = Start-Process -FilePath $fullPath -ArgumentList "dev" -PassThru -WindowStyle Hidden
        Write-Success "Process launched successfully (PID: $($process.Id))"
    }
    catch {
        Write-Error "Process launch failed: $_"
        return $false
    }
    Write-Host ""

    # 4. Wait (allow CefSharp to initialize)
    Write-Info "[Step 4] Waiting for CefSharp initialization ($WaitSeconds seconds)"
    for ($i = $WaitSeconds; $i -gt 0; $i--) {
        Write-Host "  $i seconds remaining..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    Write-Host "  Done                "

    # 4.5. Check processes after launch
    $beforeCount = Get-CefSharpSubprocessCount
    Write-Info "CefSharp subprocess count after launch: $beforeCount"
    Write-Host ""

    # 5. Force terminate the process
    Write-Info "[Step 5] Forcing process shutdown"
    try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        Write-Warning "Main process force-terminated (PID: $($process.Id))"
    }
    catch {
        Write-Error "Process termination failed: $_"
        return $false
    }
    Write-Host ""

    # 6. Wait briefly (ensure process fully exits)
    Write-Info "[Step 6] Waiting for process exit (2 seconds)"
    Start-Sleep -Seconds 2
    Write-Host ""

    # 7. Check subprocesses
    Write-Info "[Step 7] Checking CefSharp subprocesses"
    $leakedCount = Show-CefSharpSubprocesses
    Write-Host ""

    # 8. Evaluate results
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Test Results #$Iteration" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    if ($leakedCount -gt 0) {
        Write-Error "Failure: $leakedCount CefSharp subprocess(es) remain"
        Write-Warning "This indicates a memory/process leak"
        return $false
    }
    else {
        Write-Success "Success: All subprocesses were cleaned up"
        return $true
    }
}

# Script execution entry point
Write-Host @"

╔═══════════════════════════════════════════════════════╗
║   CefSharp Subprocess Leak Test                      ║
║   OyasumiVR Overlay Sidecar                          ║
╚═══════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Info "Configuration:"
Write-Host "  Executable: $ExePath"
Write-Host "  Wait time: $WaitSeconds seconds"
Write-Host "  Test iterations: $TestIterations"
Write-Host ""

# Cleanup-only mode
if ($CleanupOnly) {
    Write-Warning "Running in cleanup-only mode..."
    Cleanup-SidecarProcesses
    Cleanup-CefSharpProcesses
    Write-Success "Cleanup complete"
    exit 0
}

# Execute tests
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
        Write-Host "`nWaiting 3 seconds before the next test..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
}

# Final results
Write-Host "`n`n" -NoNewline
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Final Results                                       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total tests: $TestIterations" -ForegroundColor White
Write-Success "Passes: $successCount"
Write-Error "Failures: $failCount"
Write-Host ""

if ($failCount -gt 0) {
    Write-Error "Subprocess leaks were detected!"
    Write-Warning "Remediation required."
    exit 1
}
else {
    Write-Success "All tests completed successfully!"
    exit 0
}
