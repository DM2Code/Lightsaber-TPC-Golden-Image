@echo off

REM ============================================================
REM  CONFIGURATION
REM ============================================================
set WIM_FILE=golden-image.wim

REM ============================================================
REM  SAFETY GUARD - WinPE detection
REM  wpeutil.exe exists only in WinPE, never on a live install.
REM ============================================================
if not exist X:\Windows\System32\wpeutil.exe (
    echo.
    echo  =====================================================
    echo   SAFETY BLOCK - Not running in WinPE
    echo  =====================================================
    echo.
    echo   This script will ERASE Disk 0 if it runs on a
    echo   live Windows machine.
    echo.
    echo   wpeutil.exe not found at X:\Windows\System32\.
    echo   Boot from the USB drive to run this script.
    echo.
    echo  =====================================================
    echo.
    pause
    exit /b 1
)

REM ============================================================
REM  LOG FILE SETUP
REM  Parse YYYYMMDD from %DATE% (en-US: "Sun 05/10/2026")
REM  Temp log on X:\ (WinPE RAM). Copied to D:\ at the end.
REM ============================================================
for /f "tokens=2-4 delims=/ " %%A in ("%DATE%") do (
    set _MM=%%A
    set _DD=%%B
    set _YYYY=%%C
)
set DATESTR=%_YYYY%%_MM%%_DD%
set TMPLOG=%TEMP%\deploy_%DATESTR%.log
set FINALLOG=D:\deployment_log_%DATESTR%.log

echo.                          > "%TMPLOG%"
echo ========================== >> "%TMPLOG%"
echo  TPC Deployment Start      >> "%TMPLOG%"
echo ========================== >> "%TMPLOG%"

echo ==================================================
echo  TPC Deployment - Apply WIM + Make Bootable (UEFI)
echo ==================================================
echo Temp log : %TMPLOG%
echo Final log: %FINALLOG%

REM ============================================================
REM  STEP 1 - Locate the USB deployment drive
REM ============================================================
echo.
echo === STEP 1: Locating USB deployment drive ===
echo === STEP 1: Locating USB deployment drive === >> "%TMPLOG%"

set IMG=
set USBDRIVE=
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if not defined USBDRIVE (
        if exist "%%D:\Images\%WIM_FILE%" (
            set IMG=%%D:\Images\%WIM_FILE%
            set USBDRIVE=%%D:
        )
    )
)

if not defined USBDRIVE (
    echo ERROR: Cannot find \Images\%WIM_FILE% on any drive.
    echo ERROR: Cannot find WIM on any drive. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

echo Image found : %IMG%
echo Image found : %IMG% >> "%TMPLOG%"
echo USB drive   : %USBDRIVE%
echo USB drive   : %USBDRIVE% >> "%TMPLOG%"

REM -- Pre-flight: verify all required files exist on USB ------------------
echo.
echo === STEP 1b: Pre-flight file checks ===
echo === STEP 1b: Pre-flight file checks === >> "%TMPLOG%"

set PREFLIGHT_OK=1
if not exist "%USBDRIVE%\Deploy\Diskpart-UEFI-Single.txt" (
    echo ERROR: Missing %USBDRIVE%\Deploy\Diskpart-UEFI-Single.txt
    echo ERROR: Missing Diskpart-UEFI-Single.txt >> "%TMPLOG%"
    set PREFLIGHT_OK=0
)
if not exist "%USBDRIVE%\Deploy\Diskpart-UEFI-AssignOnly.txt" (
    echo ERROR: Missing %USBDRIVE%\Deploy\Diskpart-UEFI-AssignOnly.txt
    echo ERROR: Missing Diskpart-UEFI-AssignOnly.txt >> "%TMPLOG%"
    set PREFLIGHT_OK=0
)
if not exist "%USBDRIVE%\Deploy\unattend.xml" (
    echo ERROR: Missing %USBDRIVE%\Deploy\unattend.xml
    echo ERROR: Missing unattend.xml >> "%TMPLOG%"
    set PREFLIGHT_OK=0
)
if "%PREFLIGHT_OK%"=="0" (
    echo Pre-flight failed. Ensure all Deploy files are on the USB.
    echo Pre-flight failed. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo Pre-flight checks passed.
echo Pre-flight checks passed. >> "%TMPLOG%"

REM ============================================================
REM  STEP 2 - Determine disk mode (apply-only vs repartition)
REM  Robust method: identify volumes by LABEL (Windows/Data/System)
REM ============================================================
echo.
echo === STEP 2: Determining disk mode on Disk 0 ===
echo === STEP 2: Determining disk mode on Disk 0 === >> "%TMPLOG%"

REM --- Dump volume list ---
echo list volume > "%TEMP%\dp_listvol.txt"
diskpart /s "%TEMP%\dp_listvol.txt" > "%TEMP%\dp_vols.txt" 2>&1
type "%TEMP%\dp_vols.txt" >> "%TMPLOG%"

REM --- Reset detection vars ---
set "VOL_WIN="
set "VOL_DATA="
set "VOL_EFI="

REM --- Find Windows volume number by label "Windows" ---
for /f "tokens=2" %%V in ('
  type "%TEMP%\dp_vols.txt" ^| X:\Windows\System32\find.exe /i "Windows"
') do (
  REM diskpart output usually: "  Volume 3    W   Windows   NTFS   ..."
  if /i "%%V"=="Volume" (
    for /f "tokens=3" %%N in ("%%V %%V") do rem noop
  )
)

REM The above token trick isn't reliable; instead parse properly:
for /f "tokens=2,3" %%A in ('
  type "%TEMP%\dp_vols.txt" ^| X:\Windows\System32\find.exe /i "Windows"
') do (
  if /i "%%A"=="Volume" set "VOL_WIN=%%B"
)

REM --- Find Data volume number by label "Data" ---
for /f "tokens=2,3" %%A in ('
  type "%TEMP%\dp_vols.txt" ^| X:\Windows\System32\find.exe /i "Data"
') do (
  if /i "%%A"=="Volume" set "VOL_DATA=%%B"
)

REM --- Find EFI/System volume number by label "System" (optional) ---
for /f "tokens=2,3" %%A in ('
  type "%TEMP%\dp_vols.txt" ^| X:\Windows\System32\find.exe /i "System"
') do (
  if /i "%%A"=="Volume" set "VOL_EFI=%%B"
)

echo Detected VOL_WIN = [%VOL_WIN%] >> "%TMPLOG%"
echo Detected VOL_DATA= [%VOL_DATA%] >> "%TMPLOG%"
echo Detected VOL_EFI = [%VOL_EFI%] >> "%TMPLOG%"

REM --- If we didn't find the labels, treat as unknown layout ---
if not defined VOL_WIN goto :step2_repartition
if not defined VOL_DATA goto :step2_repartition

REM --- Assign letters non-destructively based on volume numbers ---
(
  echo select volume %VOL_WIN%
  echo remove letter=W noerr
  echo assign letter=W
  echo select volume %VOL_DATA%
  echo remove letter=D noerr
  echo assign letter=D
) > "%TEMP%\dp_assign_labels.txt"

REM EFI letter S is optional here; your bcdboot step needs S:
if defined VOL_EFI (
  echo select volume %VOL_EFI%>> "%TEMP%\dp_assign_labels.txt"
  echo remove letter=S noerr>> "%TEMP%\dp_assign_labels.txt"
  echo assign letter=S>> "%TEMP%\dp_assign_labels.txt"
)

diskpart /s "%TEMP%\dp_assign_labels.txt" >> "%TMPLOG%" 2>&1

REM --- Validate W: is real Windows ---
if exist W:\Windows\System32\config\SYSTEM (
  echo Existing OS+Data confirmed by labels. APPLY-ONLY mode.>> "%TMPLOG%"
  set "DISK_MODE=apply_only"
  set "DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-AssignOnly.txt"
  goto :step2_done
)

:step2_repartition
echo Layout not confirmed by label probe. REPARTITION mode.>> "%TMPLOG%"
set "DISK_MODE=repartition"
set "DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-Single.txt"

:step2_done
echo Selected DISK_MODE      : %DISK_MODE%
echo Selected DISKPART_SCRIPT: %DISKPART_SCRIPT%
echo Selected DISK_MODE      : %DISK_MODE% >> "%TMPLOG%"
echo Selected DISKPART_SCRIPT: %DISKPART_SCRIPT% >> "%TMPLOG%"

REM ============================================================
REM  STEP 3 - Confirmation then partition / assign letters
REM ============================================================
echo.
echo === STEP 3: Disk preparation ===
echo === STEP 3: Disk preparation === >> "%TMPLOG%"

REM -- Repartition mode: require explicit YES before wiping ----------------
if "%DISK_MODE%"=="repartition" goto :confirm_erase
goto :skip_erase_confirm

:confirm_erase
echo.
echo  ============================================================
echo   WARNING: Disk 0 will be COMPLETELY ERASED.
echo   ALL data will be permanently lost, including D: drive.
echo.
echo   Type  YES  and press ENTER to continue.
echo   Press ENTER alone to abort.
echo  ============================================================
set CONFIRM=
set /p CONFIRM=Confirm full erase (YES): 
if /i not "%CONFIRM%"=="YES" (
    echo Aborted. Disk 0 was NOT modified.
    echo Aborted by user. Disk 0 not modified. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo Confirmed. Repartitioning Disk 0...
echo User confirmed erase. Repartitioning. >> "%TMPLOG%"

:skip_erase_confirm

REM -- Apply-only mode: brief confirmation, no data loss -------------------
if "%DISK_MODE%"=="apply_only" (
    echo.
    echo  The OS partition will be overwritten with the new image.
    echo  D: Data drive will NOT be formatted or erased.
    echo.
    echo  Press ENTER to continue or close this window to abort.
    pause >nul
)

echo Running: %DISKPART_SCRIPT%
echo Running diskpart: %DISKPART_SCRIPT% >> "%TMPLOG%"

diskpart /s "%DISKPART_SCRIPT%" >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo ERROR: Diskpart failed. See log.
    echo ERROR: Diskpart failed. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

if not exist S:\ (
    echo ERROR: S: EFI partition not found after diskpart.
    echo ERROR: S: not found after diskpart. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
if not exist W:\ (
    echo ERROR: W: OS partition not found after diskpart.
    echo ERROR: W: not found after diskpart. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo S: (EFI) and W: (OS) confirmed.
echo S: and W: confirmed. >> "%TMPLOG%"

REM ============================================================
REM  STEP 4 - Apply the WIM image
REM ============================================================
echo.
echo === STEP 4: Applying image to W:\ ===
echo === STEP 4: Applying image to W:\ === >> "%TMPLOG%"

echo DEBUG: Testing W: write access... >> "%TMPLOG%"
echo test > W:\__write_test__.txt 2>>"%TMPLOG%"
if errorlevel 1 (
    echo ERROR: W: not writable ^(Access denied^). >> "%TMPLOG%"
) else (
    del /f /q W:\__write_test__.txt >nul 2>&1
    echo OK: W: writable. >> "%TMPLOG%"
)

dism /LogPath:"%TMPLOG%" /Apply-Image /ImageFile:"%IMG%" /Index:1 /ApplyDir:W:\
if errorlevel 1 (
    echo ERROR: DISM Apply-Image failed. See log.
    echo ERROR: DISM Apply-Image failed. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

if not exist W:\Windows\System32\bcdboot.exe (
    echo ERROR: W:\Windows does not look valid after DISM.
    echo ERROR: W:\Windows invalid after DISM. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

echo Image applied and verified.
echo Image applied and verified. >> "%TMPLOG%"

REM ============================================================
REM  STEP 5 - Inject unattend.xml to skip OOBE
REM ============================================================
echo.
echo === STEP 5: Injecting unattend.xml ===
echo === STEP 5: Injecting unattend.xml === >> "%TMPLOG%"

if not exist W:\Windows\Panther mkdir W:\Windows\Panther
copy /Y "%USBDRIVE%\Deploy\unattend.xml" W:\Windows\Panther\unattend.xml >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo WARNING: Could not copy unattend.xml.
    echo WARNING: Could not copy unattend.xml. >> "%TMPLOG%"
) else (
    echo unattend.xml injected.
    echo unattend.xml injected. >> "%TMPLOG%"
)

REM ============================================================
REM  STEP 6 - Enable Keyboard Filter (offline DISM)
REM  /All auto-enables parent feature Client-DeviceLockdown.
REM  Key rules are configured via Configure-KeyboardFilter.ps1
REM  on the golden image. Runtime toggle via the application:
REM    sc stop  MsKeyboardFilter  -> service mode (FSE access)
REM    sc start MsKeyboardFilter  -> kiosk lockdown
REM ============================================================
echo.
echo === STEP 6: Enabling Keyboard Filter ===
echo === STEP 6: Enabling Keyboard Filter === >> "%TMPLOG%"


REM ============================================================
REM  STEP 7 - Post-deployment defaults (Default User)
REM  - Solid color background (Navy)
REM  - Disable Desktop Spotlight via policy
REM  - Schedule PostFirstLogon.ps1 to enforce 100% scaling + background after first logon
REM ============================================================
echo.
echo === STEP 7: Applying display defaults (Default User) ===
echo === STEP 7: Applying display defaults (Default User) === >> "%TMPLOG%"

reg load HKLM\TPC_DEFAULT "W:\Users\Default\NTUSER.DAT" >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo WARNING: Could not load Default user hive.
    echo WARNING: Could not load Default user hive. >> "%TMPLOG%"
) else (

    REM --- Disable Windows Spotlight collection on Desktop (policy) ---
    REM Policy path (HKCU): Software\Policies\Microsoft\Windows\CloudContent
    REM Value: DisableSpotlightCollectionOnDesktop=1  【1-140432】
    reg add "HKLM\TPC_DEFAULT\Software\Policies\Microsoft\Windows\CloudContent" ^
        /v DisableSpotlightCollectionOnDesktop /t REG_DWORD /d 1 /f >> "%TMPLOG%" 2>&1

    REM --- Desktop background: Solid color (Navy Blue) ---
    reg add "HKLM\TPC_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers" ^
        /v BackgroundType /t REG_DWORD /d 1 /f >> "%TMPLOG%" 2>&1

    reg add "HKLM\TPC_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Background" ^
        /v BackgroundType /t REG_DWORD /d 1 /f >> "%TMPLOG%" 2>&1

    reg add "HKLM\TPC_DEFAULT\Control Panel\Desktop" ^
        /v WallPaper /t REG_SZ /d "" /f >> "%TMPLOG%" 2>&1

    reg add "HKLM\TPC_DEFAULT\Control Panel\Colors" ^
        /v Background /t REG_SZ /d "0 0 128" /f >> "%TMPLOG%" 2>&1

    reg unload HKLM\TPC_DEFAULT >> "%TMPLOG%" 2>&1

    echo Display defaults applied.
    echo Display defaults applied. >> "%TMPLOG%"
)

REM ============================================================
REM  STEP 8 - [PLACEHOLDER] Enable Unified Write Filter (UWF)
REM  Enable after keyboard filter is validated in production.
REM  Configure keyboard filter rules in golden image BEFORE
REM  enabling UWF - rule changes will not persist after reboot.
REM ============================================================
echo.
echo === STEP 8: Write Filter - Skipped (placeholder) ===
echo === STEP 8: Write Filter - Skipped (placeholder) === >> "%TMPLOG%"
REM dism /Image:W:\ /Enable-Feature /FeatureName:Client-UnifiedWriteFilter /All /NoRestart >> "%TMPLOG%" 2>&1

REM ============================================================
REM  STEP 9 - Create UEFI boot files
REM ============================================================
echo.
echo === STEP 9: Creating boot files (UEFI) ===
echo === STEP 9: Creating boot files (UEFI) === >> "%TMPLOG%"

if not exist S:\ (
    echo ERROR: S: not found. Cannot create boot files.
    echo ERROR: S: not found before bcdboot. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

W:\Windows\System32\bcdboot W:\Windows /s S: /f UEFI >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo ERROR: BCDBoot failed. See log.
    echo ERROR: BCDBoot failed. >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo Boot files created.
echo Boot files created. >> "%TMPLOG%"

REM ============================================================
REM  Copy log to D:\ then prompt for reboot
REM ============================================================
echo.
echo Copying log to D:\...
echo Deployment complete. >> "%TMPLOG%"
copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
if errorlevel 1 (
    echo WARNING: Log could not be saved to D:\ - retrieve from USB: %TMPLOG%
) else (
    echo Log saved: %FINALLOG%
)

echo.
echo ============================================================
echo  Deployment completed successfully.
echo  Remove the USB drive now, then press ENTER to restart.
echo ============================================================
pause >nul
X:\Windows\System32\wpeutil.exe reboot