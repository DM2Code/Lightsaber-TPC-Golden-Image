<#
.SYNOPSIS
  Creates a 2-partition Capture USB:
    - Partition 1: FAT32 labeled WINPE   (default 2048 MB, marked active on MBR)
    - Partition 2: NTFS labeled CAPTURE  (remainder of disk, for WIM files + scripts)

.DESCRIPTION
  Defaults to MBR for maximum BIOS/USB boot compatibility.
  GPT mode creates a proper EFI System Partition (ESP) GUID on the WinPE partition
  so UEFI firmware will recognize it as a bootable ESP.

  BitLocker note: do NOT reboot your technician machine with this USB plugged in.
  Attaching a bootable USB can shift TPM PCR measurements and trigger BitLocker
  recovery. Eject the USB before rebooting, or suspend BitLocker first:
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1

.PARAMETER WinPESizeMB
  Size in MB for the WinPE (FAT32) partition. Minimum 512 MB. Default 2048 MB.

.PARAMETER PartitionStyle
  MBR (default) or GPT.

.PARAMETER CreateFoldersAndReadme
  When set, creates an Images\, Capture\, and Logs\ folder skeleton plus a
  README-CAPTURE.txt on the CAPTURE partition. Default: enabled.

.EXAMPLE
  .\FormatUsbCapture.ps1
  .\FormatUsbCapture.ps1 -WinPESizeMB 3072 -PartitionStyle GPT
  .\FormatUsbCapture.ps1 -CreateFoldersAndReadme:$false

.NOTES
  Run as Administrator.
#>

[CmdletBinding()]
param(
  [ValidateRange(512, [int]::MaxValue)]
  [int]$WinPESizeMB = 2048,

  [ValidateSet("MBR", "GPT")]
  [string]$PartitionStyle = "MBR",

  [switch]$CreateFoldersAndReadme = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── EFI System Partition type GUID (required for UEFI boot on GPT) ────────────
$ESP_GUID = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

# ─────────────────────────────────────────────────────────────────────────────
function Assert-AdminPrivilege {
  $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run in an elevated PowerShell session (Run as Administrator)."
  }
}

function Get-VolumeSafely {
  param([Microsoft.Management.Infrastructure.CimInstance]$Partition)
  # Resolve volume from the partition object directly — avoids label collisions
  # if another disk already has a WINPE/CAPTURE label mounted.
  $vol = $Partition | Get-Volume -ErrorAction SilentlyContinue
  if (-not $vol) {
    throw "Could not resolve volume for partition $($Partition.PartitionNumber) on disk $($Partition.DiskNumber)."
  }
  return $vol
}

# ─────────────────────────────────────────────────────────────────────────────
Assert-AdminPrivilege

Write-Host "`nAvailable disks:`n" -ForegroundColor Cyan
Get-Disk | Sort-Object Number |
  Format-Table Number, FriendlyName, SerialNumber, BusType,
                @{N='Size (GB)'; E={[math]::Round($_.Size/1GB, 1)}},
                PartitionStyle -AutoSize

$diskNumber = Read-Host "`nEnter the DISK NUMBER of the USB drive to ERASE (CAPTURE USB)"
$disk = Get-Disk -Number $diskNumber -ErrorAction Stop

Write-Host "`nYou selected:" -ForegroundColor Yellow
$disk | Format-List Number, FriendlyName, SerialNumber, BusType,
                     @{N='Size (GB)'; E={[math]::Round($_.Size/1GB, 1)}},
                     PartitionStyle

# ── Guard: non-USB bus type ───────────────────────────────────────────────────
if ($disk.BusType -ne "USB") {
  Write-Warning "This disk does not report BusType=USB. Proceed ONLY if you are absolutely certain this is not an internal drive."
}

# ── Guard: WinPE size vs. actual disk size ────────────────────────────────────
$diskSizeMB = [math]::Floor($disk.Size / 1MB)
$minCaptureMB = 100  # leave at least 100 MB for the CAPTURE partition
if ($WinPESizeMB -ge ($diskSizeMB - $minCaptureMB)) {
  throw "WinPE size (${WinPESizeMB} MB) is too large for this disk (${diskSizeMB} MB). " +
        "Not enough space for the CAPTURE partition."
}

# ── Confirmation ──────────────────────────────────────────────────────────────
Write-Host "`n*** CAPTURE USB WARNING ***" -ForegroundColor Red
Write-Host "This USB is intended for CAPTURE operations (writing WIM files)." -ForegroundColor Red
Write-Host "You are about to ERASE Disk $diskNumber completely." -ForegroundColor Red

$confirm = Read-Host "Type ERASE-CAPTURE to confirm you want to wipe Disk $diskNumber"
if ($confirm -ne "ERASE-CAPTURE") {
  Write-Host "Cancelled." -ForegroundColor Yellow
  exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Suppress the "You need to format the disk" AutoPlay dialog.
# ShellHWDetection is the Windows service that generates that popup whenever it
# sees a new or unrecognized volume appear on the bus — stopping it for the
# duration of the script is the only reliable way to prevent the dialog.
# The try/finally guarantees the service is restored even if the script throws.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`nStopping ShellHWDetection to suppress AutoPlay dialogs..." -ForegroundColor DarkGray
Stop-Service -Name ShellHWDetection -Force -ErrorAction SilentlyContinue

try {

  # ── Wipe ──────────────────────────────────────────────────────────────────
  Write-Host "`nClearing disk..." -ForegroundColor Cyan
  Set-Disk -Number $diskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
  Set-Disk -Number $diskNumber -IsOffline  $false -ErrorAction SilentlyContinue
  Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false

  # ── Initialize only if needed ──────────────────────────────────────────────
  # Clear-Disk removes partitions but leaves the MBR/GPT signature intact, so
  # Windows still considers the disk "initialized". Only (re)initialize when
  # the current style doesn't match the target, or the disk is truly RAW.
  $currentStyle = (Get-Disk -Number $diskNumber).PartitionStyle
  if ($currentStyle -eq "RAW") {
    Write-Host "Initializing disk as $PartitionStyle..." -ForegroundColor Cyan
    Initialize-Disk -Number $diskNumber -PartitionStyle $PartitionStyle
  } elseif ($currentStyle -ne $PartitionStyle) {
    Write-Host "Re-initializing disk from $currentStyle to $PartitionStyle..." -ForegroundColor Cyan
    Initialize-Disk -Number $diskNumber -PartitionStyle $PartitionStyle
  } else {
    Write-Host "Disk already initialized as $PartitionStyle — skipping Initialize-Disk." -ForegroundColor DarkGray
  }

  # ── Partition 1 — WinPE (FAT32) ───────────────────────────────────────────
  Write-Host "Creating WinPE partition (${WinPESizeMB} MB, FAT32)..." -ForegroundColor Cyan

  $winpePartParams = @{
    DiskNumber = $diskNumber
    Size       = $WinPESizeMB * 1MB
  }
  if ($PartitionStyle -eq "GPT") {
    # ESP GUID so UEFI firmware treats this as a bootable EFI System Partition
    $winpePartParams['GptType'] = $ESP_GUID
  }

  $winpePart = New-Partition @winpePartParams

  if ($PartitionStyle -eq "MBR") {
    # Mark active so BIOS firmware sees this as the boot partition
    Set-Partition -DiskNumber $diskNumber -PartitionNumber $winpePart.PartitionNumber -IsActive $true
  }

  $null = Format-Volume -Partition $winpePart -FileSystem FAT32 `
            -NewFileSystemLabel "WINPE" -Confirm:$false -ErrorAction Stop

  Add-PartitionAccessPath -DiskNumber $diskNumber `
    -PartitionNumber $winpePart.PartitionNumber -AssignDriveLetter

  # ── Partition 2 — CAPTURE (NTFS) ──────────────────────────────────────────
  Write-Host "Creating CAPTURE partition (NTFS, remainder of disk)..." -ForegroundColor Cyan

  $capturePart = New-Partition -DiskNumber $diskNumber -UseMaximumSize

  $null = Format-Volume -Partition $capturePart -FileSystem NTFS `
            -NewFileSystemLabel "CAPTURE" -Confirm:$false -ErrorAction Stop

  Add-PartitionAccessPath -DiskNumber $diskNumber `
    -PartitionNumber $capturePart.PartitionNumber -AssignDriveLetter

  # ── Re-fetch partitions so drive letters are populated ────────────────────
  $winpePart   = Get-Partition -DiskNumber $diskNumber -PartitionNumber $winpePart.PartitionNumber
  $capturePart = Get-Partition -DiskNumber $diskNumber -PartitionNumber $capturePart.PartitionNumber

  # ── Resolve volumes from partition objects (avoids label collision) ────────
  $winpeVol   = Get-VolumeSafely -Partition $winpePart
  $captureVol = Get-VolumeSafely -Partition $capturePart

  Write-Host "`nDone." -ForegroundColor Green
  Write-Host ("WINPE   drive : {0}:  ({1} MB, FAT32)" -f $winpeVol.DriveLetter,   [math]::Round($winpeVol.Size/1MB))   -ForegroundColor Green
  Write-Host ("CAPTURE drive : {0}:  ({1} GB, NTFS)"  -f $captureVol.DriveLetter, [math]::Round($captureVol.Size/1GB, 1)) -ForegroundColor Green

  # ── Optional folder skeleton + README ─────────────────────────────────────
  if ($CreateFoldersAndReadme) {
    $capRoot = "$($captureVol.DriveLetter):\"

    Write-Host "`nCreating folder structure on CAPTURE partition..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path (Join-Path $capRoot "Images")  -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $capRoot "Capture") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $capRoot "Logs")    -Force | Out-Null

    $readme = @"
CAPTURE USB (WinPE + NTFS data)

WINPE partition (FAT32):
  - Copy WinPE ISO contents here (bootable)

CAPTURE partition (NTFS):
  \Images\   -> Captured .wim files will be written here
  \Capture\  -> Put Capture-TPC.cmd (and any helper scripts) here
  \Logs\     -> Optional log output location

Typical capture workflow:
  1) On reference TPC: sysprep /generalize /oobe /shutdown
  2) Boot this USB into WinPE
  3) Run the capture script:
       X:\> $($captureVol.DriveLetter):\Capture\Capture-TPC.cmd
  4) Verify the .wim appears in \Images\
"@

    Set-Content -Path (Join-Path $capRoot "README-CAPTURE.txt") -Value $readme -Encoding ASCII
    Write-Host "Created README-CAPTURE.txt and folders: Images, Capture, Logs" -ForegroundColor Green
  }

  Write-Host "`nNext steps:" -ForegroundColor Cyan
  Write-Host "  1. Copy WinPE ISO contents     → $($winpeVol.DriveLetter):\"
  Write-Host "  2. Copy capture script(s)      → $($captureVol.DriveLetter):\Capture\"
  Write-Host "  3. Captured WIM files will go  → $($captureVol.DriveLetter):\Images\"
  Write-Host "  4. Eject USB before rebooting this machine (BitLocker TPM protection)."

} finally {
  Write-Host "`nRestarting ShellHWDetection..." -ForegroundColor DarkGray
  Start-Service -Name ShellHWDetection -ErrorAction SilentlyContinue
}