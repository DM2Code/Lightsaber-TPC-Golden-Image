<#
Creates a 2-partition Deployment USB:
  - Partition 1: FAT32 labeled WINPE (default 2048MB)
  - Partition 2: NTFS labeled DEPLOY (rest of disk)
By default uses MBR for maximum USB boot compatibility.
Run as Administrator.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [int]$WinPESizeMB = 2048,

  [Parameter(Mandatory=$false)]
  [ValidateSet("MBR","GPT")]
  [string]$PartitionStyle = "MBR"
)

function Require-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  if (-not $isAdmin) {
    throw "Run this script in an elevated PowerShell session (Run as Administrator)."
  }
}

Require-Admin

Write-Host "`nAvailable disks:`n" -ForegroundColor Cyan
Get-Disk | Sort-Object Number | Format-Table Number, FriendlyName, SerialNumber, BusType, Size, PartitionStyle -Auto

$diskNumber = Read-Host "`nEnter the DISK NUMBER of the USB drive to ERASE"
$disk = Get-Disk -Number $diskNumber -ErrorAction Stop

Write-Host "`nYou selected:" -ForegroundColor Yellow
$disk | Format-List Number, FriendlyName, SerialNumber, BusType, Size, PartitionStyle

if ($disk.BusType -ne "USB") {
  Write-Host "`nWARNING: This disk does not report BusType=USB. Proceed ONLY if you are 100% sure." -ForegroundColor Red
}

$confirm = Read-Host "Type ERASE to confirm you want to wipe Disk $diskNumber"
if ($confirm -ne "ERASE") {
  Write-Host "Cancelled." -ForegroundColor Yellow
  exit 1
}

# Wipe and initialize
Write-Host "`nClearing disk..." -ForegroundColor Cyan
$disk | Set-Disk -IsReadOnly $false -ErrorAction SilentlyContinue
$disk | Set-Disk -IsOffline $false -ErrorAction SilentlyContinue
$disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false

Write-Host "Initializing disk as $PartitionStyle..." -ForegroundColor Cyan
Initialize-Disk -Number $diskNumber -PartitionStyle $PartitionStyle

# Create WINPE partition
Write-Host "Creating WINPE partition (${WinPESizeMB}MB FAT32)..." -ForegroundColor Cyan
$winpePart = New-Partition -DiskNumber $diskNumber -Size ($WinPESizeMB * 1MB) -AssignDriveLetter
Format-Volume -Partition $winpePart -FileSystem FAT32 -NewFileSystemLabel "WINPE" -Confirm:$false

# Create DEPLOY partition (rest)
Write-Host "Creating DEPLOY partition (NTFS)..." -ForegroundColor Cyan
$deployPart = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $deployPart -FileSystem NTFS -NewFileSystemLabel "DEPLOY" -Confirm:$false

# Output drive letters
$winpeVol  = Get-Volume -FileSystemLabel "WINPE"
$deployVol = Get-Volume -FileSystemLabel "DEPLOY"

Write-Host "`nDone." -ForegroundColor Green
Write-Host ("WINPE  drive: {0}:" -f $winpeVol.DriveLetter) -ForegroundColor Green
Write-Host ("DEPLOY drive: {0}:" -f $deployVol.DriveLetter) -ForegroundColor Green
Write-Host "`nNext: copy WinPE ISO contents to WINPE, and copy WIM/scripts to DEPLOY." -ForegroundColor Cyan