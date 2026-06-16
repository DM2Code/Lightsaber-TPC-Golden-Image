$ErrorActionPreference = 'Stop'

$target = 'D:\WindowsLogs'
$base   = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog'

# Wait briefly for D: to exist
$maxAttempts = 30
$attempt = 0
while (-not (Test-Path 'D:\') -and $attempt -lt $maxAttempts) {
    Start-Sleep -Seconds 2
    $attempt++
}

if (-not (Test-Path 'D:\')) {
    throw 'D: drive not found. Cannot redirect event logs.'
}

New-Item -ItemType Directory -Path $target -Force | Out-Null

# Permissions
cmd /c 'icacls D:\WindowsLogs /grant "SYSTEM:(OI)(CI)F"' | Out-Null
cmd /c 'icacls D:\WindowsLogs /grant "Administrators:(OI)(CI)F"' | Out-Null

# Redirect standard logs
$logs = @('Application', 'System', 'Security', 'Setup')

foreach ($logName in $logs) {
    $regPath = Join-Path $base $logName
    $newPath = Join-Path $target "$logName.evtx"

    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name File -Value $newPath
    }
}

Write-Host "Windows Event Logs redirected to $target"
exit 0