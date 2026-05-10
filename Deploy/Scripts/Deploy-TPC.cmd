@echo off
setlocal enabledelayedexpansion

echo ==================================================
echo  TPC Deployment - Apply WIM + Make Bootable (UEFI)
echo ==================================================

REM Find the USB volume containing the image
set IMG=
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  if exist %%D:\Images\golden-image.wim (
    set IMG=%%D:\Images\golden-image.wim
    set USBDRIVE=%%D:
    goto :found
  )
)

:found
if not defined IMG (
  echo ERROR: Cannot find \Images\golden-image.wim on any drive letter.
  echo Make sure the WIM is at:  DEPLOY:\Images\golden-image.wim
  pause
  exit /b 1
)

echo Found image at: %IMG%
echo Using USB drive: %USBDRIVE%

echo.
echo WARNING: This will ERASE the internal disk (Disk 0).
echo Unplug other external drives from the TPC now.
echo.
ping 127.0.0.1 -n 9 >nul

echo === Partitioning internal disk (UEFI/GPT) ===
diskpart /s %USBDRIVE%\Deploy\Diskpart-UEFI.txt
if errorlevel 1 (
  echo ERROR: Disk partitioning failed.
  pause
  exit /b 1
)

echo === Applying image to W:\ ===
dism /Apply-Image /ImageFile:%IMG% /Index:1 /ApplyDir:W:\
if errorlevel 1 (
  echo ERROR: DISM Apply-Image failed.
  pause
  exit /b 1
)

echo === Creating boot files (UEFI) ===
W:\Windows\System32\bcdboot W:\Windows /s S: /f UEFI
if errorlevel 1 (
  echo ERROR: BCDBoot failed.
  pause
  exit /b 1
)

echo.
echo Deployment completed successfully.
echo Rebooting in 5 seconds...
ping 127.0.0.1 -n 6 >nul
wpeutil reboot