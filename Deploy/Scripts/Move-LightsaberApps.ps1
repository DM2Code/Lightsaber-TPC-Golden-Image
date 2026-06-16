$baseDst = "C:\Program Files\Alcon Research"
$panelDst = Join-Path $baseDst "ls_panel"
$simDst   = Join-Path $baseDst "ls_monitor"

$appsRoot  = "C:\Windows\Setup\Apps"
$panelSrc  = Join-Path $appsRoot "ls_panel"
$simSrc    = Join-Path $appsRoot "ls_monitor"

New-Item -ItemType Directory -Path $panelDst -Force | Out-Null
New-Item -ItemType Directory -Path $simDst -Force | Out-Null

if (Test-Path $panelSrc) {
    Get-ChildItem -Path $panelSrc -Force | Move-Item -Destination $panelDst -Force
}

if (Test-Path $simSrc) {
    Get-ChildItem -Path $simSrc -Force | Move-Item -Destination $simDst -Force
}