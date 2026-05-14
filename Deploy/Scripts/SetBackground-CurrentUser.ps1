# Stage 2 – Runs as AlconUser on first logon (FirstLogonCommands)
# Safety net for re-deployments where the profile already exists.

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
if (!(Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }

Set-ItemProperty -Path $cdm -Name ContentDeliveryAllowed          -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cdm -Name SubscribedContent-338388Enabled -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cdm -Name SubscribedContent-338387Enabled -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cdm -Name RotatingLockScreenEnabled       -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cdm -Name SoftLandingEnabled              -Value 0 -Type DWord -Force
Set-ItemProperty -Path $cdm -Name SystemPaneSuggestionsEnabled    -Value 0 -Type DWord -Force

Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper      -Value ''        -Type String -Force
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '0'       -Type String -Force
Set-ItemProperty -Path 'HKCU:\Control Panel\Colors'  -Name Background     -Value '0 0 128' -Type String -Force
