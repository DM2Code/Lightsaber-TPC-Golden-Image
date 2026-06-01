Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Embedded\KeyboardFilter" `
  -Name DisableKeyboardFilterForAdministrators -Type DWord -Value 0

$svc = Get-Service | Where-Object {$_.DisplayName -eq "Microsoft Keyboard Filter"}
if ($svc) {
    Set-Service -Name $svc.Name -StartupType Automatic
    Start-Service -Name $svc.Name
}