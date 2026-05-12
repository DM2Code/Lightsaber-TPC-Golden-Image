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
    echo   wpeutil.exe not found at X:\Windows\System32\
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
REM  STEP 2 - User selects deployment mode
REM ============================================================
echo.
echo ============================================================
echo  SELECT DEPLOYMENT MODE
echo ============================================================
echo.
echo   1 - FULL FORMAT
echo       Wipe Disk 0 completely and create fresh partitions.
echo       USE WHEN: New disk, or disk layout is unknown/corrupt.
echo       WARNING : ALL data on Disk 0 will be lost.
echo.
echo   2 - WIPE OS ONLY
echo       Delete and recreate only the Windows partition.
echo       The D: Data partition is preserved untouched.
echo       USE WHEN: Redeploying an already-partitioned TPC disk.
echo.
echo ============================================================

:menu_prompt
set MODESEL=
set /p MODESEL=Enter choice (1 or 2): 
if "%MODESEL%"=="1" goto :mode_repartition
if "%MODESEL%"=="2" goto :mode_applyonly
echo Invalid input. Please type 1 or 2.
goto :menu_prompt

:mode_repartition
set "DISK_MODE=repartition"
set "DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-Single.txt"
echo.
echo Mode selected: FULL FORMAT
echo Mode selected: FULL FORMAT >> "%TMPLOG%"
goto :step2_done

:mode_applyonly
set "DISK_MODE=apply_only"
set "DISKPART_SCRIPT=%USBDRIVE%\Deploy\Diskpart-UEFI-AssignOnly.txt"
echo.
echo Mode selected: WIPE OS ONLY
echo Mode selected: WIPE OS ONLY >> "%TMPLOG%"
goto :step2_done

:step2_done
echo Diskpart script: %DISKPART_SCRIPT%
echo Diskpart script: %DISKPART_SCRIPT% >> "%TMPLOG%"

REM ============================================================
REM  STEP 3 - Confirmation then run diskpart
REM ============================================================
echo.
echo === STEP 3: Disk preparation ===
echo === STEP 3: Disk preparation === >> "%TMPLOG%"

REM -- Full format: require explicit YES before wiping entire disk ---------
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
    echo Aborted by user >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo Confirmed. Repartitioning Disk 0...
echo User confirmed full erase >> "%TMPLOG%"
goto :skip_erase_confirm

:skip_erase_confirm

REM -- Wipe OS only: brief confirmation, remind user D: is safe ------------
if "%DISK_MODE%"=="apply_only" (
    echo.
    echo  The Windows partition will be deleted and recreated.
    echo  D: Data drive will NOT be formatted or erased.
    echo.
    echo  Press ENTER to continue or close this window to abort.
    pause >nul
)

echo Running diskpart: %DISKPART_SCRIPT%
echo Running diskpart: %DISKPART_SCRIPT% >> "%TMPLOG%"

diskpart /s "%DISKPART_SCRIPT%" >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo ERROR: Diskpart failed. See log.
    echo ERROR: Diskpart failed >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

if not exist S:\ (
    echo ERROR: S: EFI partition not found after diskpart.
    echo ERROR: S: not found after diskpart >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
if not exist W:\ (
    echo ERROR: W: OS partition not found after diskpart.
    echo ERROR: W: not found after diskpart >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo S: and W: confirmed.
echo S: and W: confirmed >> "%TMPLOG%"

REM ============================================================
REM  STEP 4 - Apply the WIM image
REM ============================================================
echo.
echo === STEP 4: Applying image to W:\ ===
echo === STEP 4: Applying image to W:\ === >> "%TMPLOG%"

REM --- Safety gate: WindowsApps must NOT exist on a freshly wiped volume ---
if exist "W:\Program Files\WindowsApps" (
    echo ERROR: WindowsApps detected on W: - partition was not wiped cleanly.
    echo ERROR: WindowsApps detected - partition not wiped >> "%TMPLOG%"
    echo Use FULL FORMAT mode if WIPE OS ONLY keeps failing.
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

REM --- Run DISM ---
set "DISMLOG=X:\dism_apply_%DATESTR%.log"
dism /LogLevel:4 /LogPath:"%DISMLOG%" /Apply-Image /ImageFile:"%IMG%" /Index:1 /ApplyDir:W:\
set "DISM_RC=%errorlevel%"

if exist "%DISMLOG%" type "%DISMLOG%" >> "%TMPLOG%"

if not "%DISM_RC%"=="0" (
    echo ERROR: DISM Apply-Image failed. RC=%DISM_RC%
    echo ERROR: DISM failed RC=%DISM_RC% >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b %DISM_RC%
)

if not exist W:\Windows\System32\bcdboot.exe (
    echo ERROR: W:\Windows does not look valid after DISM.
    echo ERROR: W:\Windows invalid after DISM >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

echo Image applied and verified.
echo Image applied and verified >> "%TMPLOG%"

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
    echo WARNING: Could not copy unattend.xml >> "%TMPLOG%"
) else (
    echo unattend.xml injected.
    echo unattend.xml injected >> "%TMPLOG%"
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
REM  STEP 7 - Post-deployment display defaults
REM  Applied to Default user profile so AlconUser inherits.
REM  - Display scale : 100% (96 DPI)
REM  - Desktop       : solid Navy Blue (RGB 0 0 128)
REM  - Wallpaper     : none
REM ============================================================
echo.
echo === STEP 7: Applying display defaults ===
echo === STEP 7: Applying display defaults === >> "%TMPLOG%"

reg load HKLM\TPC_DEFAULT W:\Users\Default\NTUSER.DAT >> "%TMPLOG%" 2>&1
if not errorlevel 1 (
    reg add "HKLM\TPC_DEFAULT\Control Panel\Desktop" /v LogPixels      /t REG_DWORD /d 96 /f >> "%TMPLOG%" 2>&1
    reg add "HKLM\TPC_DEFAULT\Control Panel\Desktop" /v Win8DpiScaling /t REG_DWORD /d 1  /f >> "%TMPLOG%" 2>&1
    reg unload HKLM\TPC_DEFAULT >> "%TMPLOG%" 2>&1
    echo Display defaults applied.
    echo Display defaults applied >> "%TMPLOG%"
) else (
    echo WARNING: Could not load Default user hive.
    echo WARNING: Could not load Default user hive >> "%TMPLOG%"
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
    echo ERROR: S: not found before bcdboot >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)

W:\Windows\System32\bcdboot W:\Windows /s S: /f UEFI >> "%TMPLOG%" 2>&1
if errorlevel 1 (
    echo ERROR: BCDBoot failed. See log.
    echo ERROR: BCDBoot failed >> "%TMPLOG%"
    copy /Y "%TMPLOG%" "%FINALLOG%" >nul 2>&1
    pause
    exit /b 1
)
echo Boot files created.
echo Boot files created >> "%TMPLOG%"

REM ============================================================
REM  Copy log to D:\ then prompt for reboot
REM ============================================================
echo.
echo Copying log to D:\...
echo Deployment complete >> "%TMPLOG%"
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