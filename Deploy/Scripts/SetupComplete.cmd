@echo off
setlocal

echo [%date% %time%] SetupComplete started >> D:\SetupComplete.log 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\Redirect-EventLogs.ps1" >> D:\SetupComplete.log 2>&1

echo [%date% %time%] SetupComplete finished with exit code %ERRORLEVEL% >> D:\SetupComplete.log 2>&1

exit /b 0