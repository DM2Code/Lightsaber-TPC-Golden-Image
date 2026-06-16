$WshShell = New-Object -ComObject WScript.Shell
$Desktop   = [Environment]::GetFolderPath('Desktop')

$shortcuts = @(
    @{
        Name = 'Lightsaber Panel'
        TargetPath = 'C:\Program Files\Alcon Research\ls_panel\ls_panel.exe'
    },
    @{
        Name = 'Lightsaber Monitor'
        TargetPath = 'C:\Program Files\Alcon Research\ls_monitor\ls_monitor.exe'
    }
)

foreach ($item in $shortcuts) {
    $shortcutPath = Join-Path $Desktop ($item.Name + '.lnk')
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $item.TargetPath
    $shortcut.Save()
}