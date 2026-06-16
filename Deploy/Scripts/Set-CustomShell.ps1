$ErrorActionPreference = 'Stop'

$logFile = 'D:\SetCustomShell.log'
$winlogonKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$appPath = 'C:\Program Files\Alcon Research\ls_monitor\ls_monitor.exe'

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "$timestamp $Message"
}

try {
    Write-Log "Setting custom shell to: $appPath"

    if (-not (Test-Path $appPath)) {
        throw "Shell executable not found: $appPath"
    }

    Set-ItemProperty -Path $winlogonKey -Name 'Shell' -Value $appPath

    Write-Log "Custom shell configured successfully."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}