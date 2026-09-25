param(
    [ValidateSet(1, 2)]
    [int]$Takes,
    [int]$Steps = 20,
    [string]$GodotPath = 'C:\Godot-472\Godot_v4.7.2-stable_win64_console.exe'
)

$ErrorActionPreference = 'Stop'
$listener = Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 8000 -State Listen |
    Select-Object -First 1
if ($null -eq $listener) {
    throw 'The Kimodo backend is not listening on 127.0.0.1:8000.'
}
$serverPid = $listener.OwningProcess
$stdoutPath = Join-Path $PSScriptRoot ".goal14-live-$Takes-stdout.log"
$stderrPath = Join-Path $PSScriptRoot ".goal14-live-$Takes-stderr.log"
Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

$arguments = @(
    '--headless', '--path', (Split-Path $PSScriptRoot -Parent),
    '--script', 'res://tests/test_live_generation.gd', '--',
    '--steps', $Steps, '--takes', $Takes
)
$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
$peakWorkingSet = 0L
$peakGpuMiB = 0
$baselineGpuMiB = [int]((& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits |
    Select-Object -First 1).Trim())
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $process.HasExited) {
    $server = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if ($null -ne $server) {
        $peakWorkingSet = [Math]::Max($peakWorkingSet, $server.WorkingSet64)
    }
    $gpuUsed = [int]((& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits |
        Select-Object -First 1).Trim())
    $peakGpuMiB = [Math]::Max($peakGpuMiB, $gpuUsed)
    Start-Sleep -Milliseconds 200
    $process.Refresh()
}
$stopwatch.Stop()
$stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
$stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
$stdout | Write-Host
$stderr | Write-Host
if ($process.ExitCode -ne 0) {
    throw "Live take test exited with code $($process.ExitCode)."
}
[pscustomobject]@{
    takes = $Takes
    steps = $Steps
    wall_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    peak_server_working_set_gib = [Math]::Round($peakWorkingSet / 1GB, 2)
    baseline_total_gpu_mib = $baselineGpuMiB
    peak_total_gpu_mib = $peakGpuMiB
} | ConvertTo-Json
