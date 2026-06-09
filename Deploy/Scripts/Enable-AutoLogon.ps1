$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon'   -Value '1'          -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultUserName'  -Value 'AlconUser'  -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultPassword'  -Value 'L1ghts@b3r' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type String