@echo off
setlocal enabledelayedexpansion

echo ==================================================
echo  TPC Deployment - Apply WIM + Make Bootable (UEFI)
echo ==================================================

REM ══════════════════════════════════════════════════
REM  CONFIGURATION  (edit these values as needed)
REM ══════════════════════════════════════════════════
REM  Name of the WIM file located under DEPLOY:\Images\
set WIM_FILE=golden-image.wim

REM ══════════════════════════════════════════════════
REM  STEP 1  Locate the USB deployment drive
REM ══════════════════════════════════════════════════
set IMG=
set USBDRIVE=
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  if exist %%D:\Images\%WIM_FILE% (
    set IMG=%%D:\Images\%WIM_FILE%
    set USBDRIVE=%%D:
    goto :found_usb
  )
)

echo ERROR: Cannot find \Images\%WIM_FILE% on any drive letter.
echo        Make sure the WIM is at:  DEPLOY:\Images\%WIM_FILE%
pause
exit /b 1

:found_usb
echo Found image at : %IMG%
echo USB drive      : %USBDRIVE%

echo.
echo WARNING: This will ERASE Disk 0 (the internal drive).
echo          Unplug any extra external drives from this device now.
echo.
ping 127.0.0.1 -n 9 >nul

REM ══════════════════════════════════════════════════
REM  STEP 2  Detect number of physical disks
REM ══════════════════════════════════════════════════
echo === Detecting physical disks ===

echo list disk > %TEMP%\dp_list.txt
diskpart /s %TEMP%\dp_list.txt > %TEMP%\disklist.txt 2>&1

REM If "Disk 1" appears in the output there are at least two physical disks.
findstr /C:"Disk 1" %TEMP%\disklist.txt >nul 2>&1
if %errorlevel% == 0 (
  echo Two or more disks detected.
  echo   Disk 0 will be formatted for the OS only.
  echo   Disk 1 ^(data drive^) will not be touched.
  set DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-Dual.txt
) else (
  echo Single disk detected.
  echo   Disk 0 will be split into an OS partition and a Data partition.
  set DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-Single.txt
)

REM ══════════════════════════════════════════════════
REM  STEP 3  Partition Disk 0
REM ══════════════════════════════════════════════════
echo === Partitioning Disk 0 using: %DISKPART_SCRIPT% ===
diskpart /s %DISKPART_SCRIPT%
if errorlevel 1 (
  echo ERROR: Disk partitioning failed.
  pause
  exit /b 1
)

REM ══════════════════════════════════════════════════
REM  STEP 4  Apply the WIM image
REM ══════════════════════════════════════════════════
echo === Applying image to W:\ ===
dism /Apply-Image /ImageFile:%IMG% /Index:1 /ApplyDir:W:\
if errorlevel 1 (
  echo ERROR: DISM Apply-Image failed.
  pause
  exit /b 1
)

REM ══════════════════════════════════════════════════
REM  STEP 5  Inject unattend.xml to skip OOBE
REM          Windows reads this file automatically from
REM          W:\Windows\Panther\ on first boot.
REM ══════════════════════════════════════════════════
echo === Injecting unattend.xml (OOBE bypass) ===
if not exist W:\Windows\Panther mkdir W:\Windows\Panther
copy /Y %USBDRIVE%\Deploy\unattend.xml W:\Windows\Panther\unattend.xml
if errorlevel 1 (
  echo WARNING: Could not copy unattend.xml.
  echo          OOBE screens will NOT be pre-configured.
)

REM ══════════════════════════════════════════════════
REM  STEP 6  Enable Keyboard Filter (offline via DISM)
REM
REM  What it does: MsKeyboardFilter lets you block or
REM  remap key combinations (Win key, Ctrl+Alt+Del, etc.)
REM  without modifying the application – ideal for kiosks.
REM
REM  Requires: Windows 10/11 Enterprise, Education, or IoT.
REM  Not available on Home or Pro editions.
REM ══════════════════════════════════════════════════
echo === Enabling Keyboard Filter feature (offline DISM) ===
set KBF_OK=0
dism /Image:W:\ /Enable-Feature /FeatureName:Client-KeyboardFilter /NoRestart
if not errorlevel 1 (
  set KBF_OK=1
  echo Keyboard Filter feature enabled.
) else (
  echo WARNING: Client-KeyboardFilter could not be enabled.
  echo          Check that this Windows edition supports the feature.
)

if "%KBF_OK%"=="1" (
  echo === Configuring MsKeyboardFilter service to start automatically ===
  REM Load the SYSTEM hive from the offline image
  reg load HKLM\TPC_SYSTEM W:\Windows\System32\config\SYSTEM
  if not errorlevel 1 (
    REM Start value 2 = Automatic
    reg add "HKLM\TPC_SYSTEM\ControlSet001\Services\MsKeyboardFilter" /v Start /t REG_DWORD /d 2 /f
    reg unload HKLM\TPC_SYSTEM
    echo MsKeyboardFilter service set to Automatic start.
  ) else (
    echo WARNING: Could not load SYSTEM hive – service start type not configured.
    echo          Run: sc.exe config MsKeyboardFilter start= auto
    echo          after first boot to configure manually.
  )
) else (
  echo Skipping service configuration ^(feature was not enabled^).
)

REM ══════════════════════════════════════════════════
REM  STEP 7  [PLACEHOLDER] Enable Unified Write Filter
REM
REM  UWF redirects all disk writes to an overlay in RAM,
REM  protecting the OS partition from unwanted changes –
REM  commonly used alongside Keyboard Filter on kiosks.
REM
REM  Uncomment and configure the lines below when ready.
REM ══════════════════════════════════════════════════
echo === [PLACEHOLDER] Write Filter - Skipped (not yet configured) ===
REM dism /Image:W:\ /Enable-Feature /FeatureName:Client-UnifiedWriteFilter /NoRestart
REM
REM  After enabling, configure UWF via offline registry or a first-boot script:
REM    reg load HKLM\TPC_SYSTEM W:\Windows\System32\config\SYSTEM
REM    reg add "HKLM\TPC_SYSTEM\ControlSet001\Services\uwfvol" /v Start /t REG_DWORD /d 2 /f
REM    reg unload HKLM\TPC_SYSTEM
REM
REM  Additional UWF volume/exclusion configuration goes here.

REM ══════════════════════════════════════════════════
REM  STEP 8  Create UEFI boot files
REM ══════════════════════════════════════════════════
echo === Creating boot files (UEFI) ===
W:\Windows\System32\bcdboot W:\Windows /s S: /f UEFI
if errorlevel 1 (
  echo ERROR: BCDBoot failed.
  pause
  exit /b 1
)

REM ══════════════════════════════════════════════════
REM  DONE
REM ══════════════════════════════════════════════════
echo.
echo ============================================================
echo  Deployment completed successfully.
echo  Remove the USB drive now, then press ENTER to restart.
echo ============================================================
pause >nul
wpeutil reboot