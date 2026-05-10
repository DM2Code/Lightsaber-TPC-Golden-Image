@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   CAPTURE-TPC - Capture WIM with Timestamp (WinPE)
echo ==========================================================
echo.
echo SAFETY:
echo  - This should be run ONLY after:
echo      sysprep /generalize /oobe /shutdown
echo  - And ONLY when booted into WinPE (X:\).
echo.
echo You will be capturing C:\ to a WIM on the CAPTURE USB.
echo.

REM ---- Verify we are in WinPE (X: drive exists and is WinPE RAM disk) ----
if not exist X:\Windows\System32\wpeinit.exe (
  echo ERROR: This does not look like WinPE (missing X:\Windows\System32\wpeinit.exe).
  echo Aborting to avoid capturing from a live OS.
  pause
  exit /b 1
)

REM ---- Find CAPTURE partition by Volume Label ----
set CAPDRIVE=
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  for /f "tokens=2 delims==" %%V in ('wmic logicaldisk where "DeviceID='%%D:'" get VolumeName /value ^| find "="') do (
    if /I "%%V"=="CAPTURE" (
      set CAPDRIVE=%%D:
      goto :foundcap
    )
  )
)

:foundcap
if not defined CAPDRIVE (
  echo ERROR: Could not find the USB partition labeled CAPTURE.
  echo Make sure your NTFS partition label is CAPTURE.
  echo Dropping to command prompt...
  cmd.exe
  exit /b 1
)

REM ---- Ensure folders exist ----
if not exist "%CAPDRIVE%\Images"  mkdir "%CAPDRIVE%\Images"
if not exist "%CAPDRIVE%\Logs"    mkdir "%CAPDRIVE%\Logs"

REM ---- Build timestamp: YYYYMMDD-HHMMSS ----
set TS=
for /f "tokens=2 delims==" %%I in ('wmic os get LocalDateTime /value ^| find "="') do set LDT=%%I
REM LDT format: YYYYMMDDhhmmss.ssssss±UUU
if defined LDT (
  set YYYY=!LDT:~0,4!
  set MM=!LDT:~4,2!
  set DD=!LDT:~6,2!
  set hh=!LDT:~8,2!
  set mi=!LDT:~10,2!
  set ss=!LDT:~12,2!
  set TS=!YYYY!!MM!!DD!-!hh!!mi!!ss!
) else (
  echo WARNING: Unable to read system time via WMIC.
  echo Using fallback timestamp.
  set TS=UNKNOWN-TIME
)

set IMGFILE=%CAPDRIVE%\Images\golden-image-!TS!.wim
set LOGFILE=%CAPDRIVE%\Logs\capture-!TS!.log

echo.
echo CAPTURE USB:   %CAPDRIVE%
echo Output WIM:    %IMGFILE%
echo Log file:      %LOGFILE%
echo.

REM ---- Last chance guardrail ----
echo WARNING: This will capture the OS from C:\ into a new WIM file.
set /p OK=Type CAPTURE to proceed: 
if /I not "%OK%"=="CAPTURE" (
  echo Cancelled.
  exit /b 2
)

REM ---- Basic sanity checks on C:\ ----
if not exist C:\Windows\System32 (
  echo ERROR: C:\Windows\System32 not found. Is C: the Windows volume?
  echo Aborting.
  pause
  exit /b 3
)

echo.
echo Starting DISM capture...
echo (This can take a while. Do not unplug the USB.)
echo.

dism /Capture-Image ^
  /ImageFile:"%IMGFILE%" ^
  /CaptureDir:C:\ ^
  /Name:"TPC Golden Image Win11 IoT LTSC 2024" ^
  /Compress:Max ^
  /CheckIntegrity ^
  /LogPath:"%LOGFILE%"

if errorlevel 1 (
  echo.
  echo ERROR: DISM capture failed. See log:
  echo   %LOGFILE%
  pause
  exit /b 10
)

echo.
echo SUCCESS: Capture completed.
echo WIM saved to:
echo   %IMGFILE%
echo.
echo Shutting down now to avoid accidental Windows boot...
wpeutil shutdown