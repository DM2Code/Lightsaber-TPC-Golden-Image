<#
Creates a 2-partition CAPTURE USB:
  - Partition 1: FAT32 labeled WINPE (default 2048MB) for UEFI boot
  - Partition 2: NTFS labeled CAPTURE (rest of disk) for captured WIM + scripts
By default uses MBR for maximum USB boot compatibility.
Run as Administrator.

After running:
  - Copy WinPE ISO contents to the WINPE partition.
  - Put your capture script(s) under CAPTURE:\Capture\
  - Captured images will be stored under CAPTURE:\Images\
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [int]$WinPESizeMB = 2048,

  [Parameter(Mandatory=$false)]
  [ValidateSet("MBR","GPT")]
  [string]$PartitionStyle = "MBR",

  # Optional: create a helpful skeleton on the CAPTURE partition
  [Parameter(Mandatory=$false)]
  [switch]$CreateFoldersAndReadme = $true
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

$diskNumber = Read-Host "`nEnter the DISK NUMBER of the USB drive to ERASE (CAPTURE USB)"
$disk = Get-Disk -Number $diskNumber -ErrorAction Stop

Write-Host "`nYou selected:" -ForegroundColor Yellow
$disk | Format-List Number, FriendlyName, SerialNumber, BusType, Size, PartitionStyle

if ($disk.BusType -ne "USB") {
  Write-Host "`nWARNING: This disk does not report BusType=USB. Proceed ONLY if you are 100% sure." -ForegroundColor Red
}

Write-Host "`n*** CAPTURE USB WARNING ***" -ForegroundColor Red
Write-Host "This USB is intended for CAPTURE operations (writing WIM files)." -ForegroundColor Red
Write-Host "You are about to ERASE Disk $diskNumber completely." -ForegroundColor Red

$confirm = Read-Host "Type ERASE-CAPTURE to confirm you want to wipe Disk $diskNumber"
if ($confirm -ne "ERASE-CAPTURE") {
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

# Create CAPTURE partition (rest)
Write-Host "Creating CAPTURE partition (NTFS)..." -ForegroundColor Cyan
$capturePart = New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $capturePart -FileSystem NTFS -NewFileSystemLabel "CAPTURE" -Confirm:$false

# Output drive letters
$winpeVol   = Get-Volume -FileSystemLabel "WINPE"
$captureVol = Get-Volume -FileSystemLabel "CAPTURE"

Write-Host "`nDone." -ForegroundColor Green
Write-Host ("WINPE   drive: {0}:" -f $winpeVol.DriveLetter) -ForegroundColor Green
Write-Host ("CAPTURE drive: {0}:" -f $captureVol.DriveLetter) -ForegroundColor Green

# Optional: create folder skeleton + README
if ($CreateFoldersAndReadme) {
  $capRoot = "{0}:\\" -f $captureVol.DriveLetter

  Write-Host "`nCreating folder structure on CAPTURE partition..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Path (Join-Path $capRoot "Images")  -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $capRoot "Capture") -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $capRoot "Logs")    -Force | Out-Null

  $readme = @"
CAPTURE USB (WinPE + NTFS data)

WINPE partition (FAT32):
  - Copy WinPE ISO contents here (bootable UEFI)

CAPTURE partition (NTFS):
  \Images\   -> Captured .wim files will go here
  \Capture\  -> Put Capture-TPC.cmd (and optional helpers) here
  \Logs\     -> Optional log output location

Typical steps:
  1) On reference TPC: sysprep /generalize /oobe /shutdown
  2) Boot this USB (WinPE)
  3) Run capture script:
       X:\> <DriveLetter>:\Capture\Capture-TPC.cmd
  4) Verify the .wim appears in \Images\
"@

  Set-Content -Path (Join-Path $capRoot "README-CAPTURE.txt") -Value $readme -Encoding ASCII
  Write-Host "Created README-CAPTURE.txt and folders: Images, Capture, Logs" -ForegroundColor Green
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1) Copy WinPE ISO contents to WINPE partition." -ForegroundColor Cyan
Write-Host "2) Put your capture script(s) in CAPTURE:\Capture\ and capture output will go to CAPTURE:\Images\" -ForegroundColor Cyan
``