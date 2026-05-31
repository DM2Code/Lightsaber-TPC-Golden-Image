<#
.SYNOPSIS
  Creates a 2-partition Deployment USB:
    - Partition 1: FAT32 labeled WINPE  (default 2048 MB, marked active on MBR)
    - Partition 2: NTFS labeled DEPLOY  (remainder of disk)

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

.EXAMPLE
  .\FormatUsbDeploy.ps1
  .\FormatUsbDeploy.ps1 -WinPESizeMB 3072 -PartitionStyle GPT

.NOTES
  Run as Administrator.
#>

[CmdletBinding()]
param(
  [ValidateRange(512, [int]::MaxValue)]
  [int]$WinPESizeMB = 2048,

  [ValidateSet("MBR", "GPT")]
  [string]$PartitionStyle = "MBR"
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
  # if another disk already has a WINPE/DEPLOY label mounted.
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

$diskNumber = Read-Host "`nEnter the DISK NUMBER of the USB drive to ERASE"
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
$minDeployMB = 100  # leave at least 100 MB for the DEPLOY partition
if ($WinPESizeMB -ge ($diskSizeMB - $minDeployMB)) {
  throw "WinPE size (${WinPESizeMB} MB) is too large for this disk (${diskSizeMB} MB). " +
        "Not enough space for the DEPLOY partition."
}

# ── Confirmation ──────────────────────────────────────────────────────────────
$confirm = Read-Host "Type ERASE to confirm you want to wipe Disk $diskNumber"
if ($confirm -ne "ERASE") {
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
    $winpePartParams['GptType'] = $ESP_GUID
  }

  $winpePart = New-Partition @winpePartParams

  if ($PartitionStyle -eq "MBR") {
    Set-Partition -DiskNumber $diskNumber -PartitionNumber $winpePart.PartitionNumber -IsActive $true
  }

  $null = Format-Volume -Partition $winpePart -FileSystem FAT32 `
            -NewFileSystemLabel "WINPE" -Confirm:$false -ErrorAction Stop

  Add-PartitionAccessPath -DiskNumber $diskNumber `
    -PartitionNumber $winpePart.PartitionNumber -AssignDriveLetter

  # ── Partition 2 — DEPLOY (NTFS) ───────────────────────────────────────────
  Write-Host "Creating DEPLOY partition (NTFS, remainder of disk)..." -ForegroundColor Cyan

  $deployPart = New-Partition -DiskNumber $diskNumber -UseMaximumSize

  $null = Format-Volume -Partition $deployPart -FileSystem NTFS `
            -NewFileSystemLabel "DEPLOY" -Confirm:$false -ErrorAction Stop

  Add-PartitionAccessPath -DiskNumber $diskNumber `
    -PartitionNumber $deployPart.PartitionNumber -AssignDriveLetter

  # ── Re-fetch partitions so drive letters are populated ────────────────────
  $winpePart  = Get-Partition -DiskNumber $diskNumber -PartitionNumber $winpePart.PartitionNumber
  $deployPart = Get-Partition -DiskNumber $diskNumber -PartitionNumber $deployPart.PartitionNumber

  # ── Resolve volumes from partition objects (avoids label collision) ────────
  $winpeVol  = Get-VolumeSafely -Partition $winpePart
  $deployVol = Get-VolumeSafely -Partition $deployPart

  Write-Host "`nDone." -ForegroundColor Green
  Write-Host ("WINPE  drive : {0}:  ({1} MB, FAT32)" -f $winpeVol.DriveLetter, [math]::Round($winpeVol.Size/1MB)) -ForegroundColor Green
  Write-Host ("DEPLOY drive : {0}:  ({1} GB, NTFS)"  -f $deployVol.DriveLetter, [math]::Round($deployVol.Size/1GB,1)) -ForegroundColor Green

  Write-Host "`nNext steps:" -ForegroundColor Cyan
  Write-Host "  1. Copy WinPE ISO contents  → $($winpeVol.DriveLetter):\"
  Write-Host "  2. Copy WIM, scripts, utils → $($deployVol.DriveLetter):\"
  Write-Host "  3. Eject USB before rebooting this machine (BitLocker TPM protection)."

} finally {
  Write-Host "`nRestarting ShellHWDetection..." -ForegroundColor DarkGray
  Start-Service -Name ShellHWDetection -ErrorAction SilentlyContinue
}