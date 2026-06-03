@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   CAPTURE-TPC - Capture WIM with Timestamp (WinPE)
echo ==========================================================
echo.
echo SAFETY:
echo  - Run ONLY after:
echo      sysprep /generalize /oobe /shutdown
echo  - Booted into WinPE (X:\)
echo.
echo This script captures C:\ into a WIM on D:\
echo.

REM ==========================================================
REM Verify WinPE
REM ==========================================================
if not exist X:\Windows\System32\wpeinit.exe (
    echo ERROR: WinPE environment not detected.
    echo Missing:
    echo   X:\Windows\System32\wpeinit.exe
    pause
    exit /b 1
)

REM ==========================================================
REM Verify Data Drive
REM ==========================================================
if not exist D:\ (
    echo ERROR: D:\ is not accessible.
    echo Make sure the data drive is mounted as D:
    pause
    exit /b 2
)


REM ==========================================================
REM Locate DATA partition on USB
REM ==========================================================
set CAPDRIVE=

for %%i in (D E F G H I J K L M N O P) do (
    vol %%i: 2>nul | find /I "CAPTURE" >nul && set CAPDRIVE=%%i:
)

REM Fail-safe
if "%CAPDRIVE%"=="" (
    echo ERROR: Data partition not found!
    pause
    exit /b 1
)


REM ==========================================================
REM Create folders
REM ==========================================================
if not exist "%CAPDRIVE%\Images" mkdir "%CAPDRIVE%\Images"
if not exist "%CAPDRIVE%\Logs"   mkdir "%CAPDRIVE%\Logs"

REM ==========================================================
REM Build timestamp using DATE and TIME
REM Compatible with minimal WinPE
REM ==========================================================
set TS=%DATE%_%TIME%

REM Replace invalid filename characters
set TS=%TS:/=-%
set TS=%TS:\=-%
set TS=%TS::=-%
set TS=%TS:.=-%
set TS=%TS:,=-%
set TS=%TS: =0%

REM Remove weekday if present
REM Example:
REM Tue 06-02-2026_07-45-11-22
REM becomes:
REM 06-02-2026_07-45-11-22

if not "%TS:~3,1%"=="-" (
    set TS=%TS:~4%
)

REM ==========================================================
REM Final filenames
REM ==========================================================
set IMGFILE=%CAPDRIVE%\Images\golden-image-%TS%.wim
set LOGFILE=%CAPDRIVE%\Logs\capture-%TS%.log

echo.
echo DATA DRIVE:    %CAPDRIVE%
echo OUTPUT WIM:    %IMGFILE%
echo LOG FILE:      %LOGFILE%
echo.

REM ==========================================================
REM Confirmation
REM ==========================================================
echo WARNING: This will capture C:\ into a new WIM image.
echo.

set /p OK=Type CAPTURE to continue: 

if /I not "%OK%"=="CAPTURE" (
    echo.
    echo Capture cancelled.
    exit /b 3
)

REM ==========================================================
REM Basic validation
REM ==========================================================
if not exist C:\Windows\System32 (
    echo.
    echo ERROR: C:\Windows\System32 not found.
    echo Is C: the Windows partition?
    pause
    exit /b 4
)

REM ==========================================================
REM Start capture
REM ==========================================================
echo.
echo Starting DISM capture...
echo This may take a while.
echo Do not remove power or storage devices.
echo.

dism /Capture-Image ^
    /ImageFile:"%IMGFILE%" ^
    /CaptureDir:C:\ ^
    /Name:"TPC Golden Image Win11 IoT LTSC 2024" ^
    /Compress:max ^
    /CheckIntegrity ^
    /LogPath:"%LOGFILE%"

if errorlevel 1 (
    echo.
    echo ERROR: DISM capture failed.
    echo Review log:
    echo   %LOGFILE%
    pause
    exit /b 10
)

echo.
echo ==========================================================
echo SUCCESS: Capture completed
echo ==========================================================
echo.
echo WIM saved to:
echo   %IMGFILE%
echo.

echo Shutting down WinPE...
wpeutil shutdown