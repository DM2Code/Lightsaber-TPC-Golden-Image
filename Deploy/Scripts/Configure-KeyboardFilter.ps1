# ==============================================================================
#  Configure-KeyboardFilter.ps1
#  Configures which key combinations MsKeyboardFilter will suppress.
#
#  WHEN TO RUN:
#    - On a RUNNING Windows instance (not during WinPE).
#    - Run as Administrator.
#    - MsKeyboardFilter service must already be enabled and running.
#      (The deploy script handles enabling it; it starts on first boot.)
#
#  RECOMMENDED USAGE:
#    Option A (Golden Image): Run this once on the reference machine before
#      capturing the WIM. The rules get baked into the image.
#    Option B (First Boot): Plant a RunOnce entry via the deploy script and
#      run this automatically on first login.
#
#  TO ADD OR REMOVE A KEY: comment/uncomment lines in the sections below.
#  To see ALL available predefined key names, run:
#    Get-WMIObject -Namespace "root\standardcimv2\embedded" -Class WEKF_PredefinedKey |
#      Select-Object Id, Enabled | Sort-Object Id
# ==============================================================================

$NAMESPACE = "root\standardcimv2\embedded"

# ------------------------------------------------------------------------------
#  Helper: enable a predefined key combo by name
# ------------------------------------------------------------------------------
function Block-PredefinedKey {
    param([string]$KeyId)
    $key = Get-WMIObject -Namespace $NAMESPACE -Class WEKF_PredefinedKey |
           Where-Object { $_.Id -eq $KeyId }
    if ($key) {
        $key.Enabled = 1
        $key.Put() | Out-Null
        Write-Host "  [BLOCKED]  $KeyId"
    } else {
        Write-Host "  [NOT FOUND] $KeyId - check spelling or Windows edition support"
    }
}

# ------------------------------------------------------------------------------
#  Helper: unblock a predefined key combo (run to undo a block)
# ------------------------------------------------------------------------------
function Unblock-PredefinedKey {
    param([string]$KeyId)
    $key = Get-WMIObject -Namespace $NAMESPACE -Class WEKF_PredefinedKey |
           Where-Object { $_.Id -eq $KeyId }
    if ($key) {
        $key.Enabled = 0
        $key.Put() | Out-Null
        Write-Host "  [UNBLOCKED] $KeyId"
    }
}

# ------------------------------------------------------------------------------
#  Helper: block a custom key combo (for combos not in the predefined list)
#  Key name format uses standard virtual-key names, e.g. "Ctrl+Alt+T"
# ------------------------------------------------------------------------------
function Block-CustomKey {
    param([string]$KeyId)
    $existing = Get-WMIObject -Namespace $NAMESPACE -Class WEKF_CustomKey |
                Where-Object { $_.Id -eq $KeyId }
    if ($existing) {
        $existing.Enabled = 1
        $existing.Put() | Out-Null
    } else {
        Set-WMIInstance -Namespace $NAMESPACE -Class WEKF_CustomKey `
            -Arguments @{ Id = $KeyId; Enabled = 1 } | Out-Null
    }
    Write-Host "  [BLOCKED]  $KeyId (custom)"
}

# ==============================================================================
#  BLOCKED KEY COMBINATIONS
#  Comment out any line you do NOT want to block.
# ==============================================================================

Write-Host ""
Write-Host "Configuring Keyboard Filter blocked keys..."
Write-Host ""

# -- Windows key (opens Start menu) -------------------------------------------
Block-PredefinedKey "Win"                  # Windows key alone

# -- Windows key combos -------------------------------------------------------
Block-PredefinedKey "Win+D"                # Show/hide desktop
Block-PredefinedKey "Win+E"                # Open File Explorer
Block-PredefinedKey "Win+F"                # Open Search / Feedback Hub
Block-PredefinedKey "Win+I"                # Open Settings
Block-PredefinedKey "Win+L"                # Lock screen
Block-PredefinedKey "Win+M"                # Minimize all windows
Block-PredefinedKey "Win+P"                # Projection options
Block-PredefinedKey "Win+R"                # Run dialog
Block-PredefinedKey "Win+S"                # Search
Block-PredefinedKey "Win+Tab"              # Task view / virtual desktops
Block-PredefinedKey "Win+U"                # Accessibility / Ease of Access
Block-PredefinedKey "Win+X"                # Power User menu (right-click Start)

# -- Task Manager / security screen -------------------------------------------
Block-PredefinedKey "Ctrl+Alt+Del"         # Security options screen
Block-PredefinedKey "Ctrl+Shift+Esc"       # Task Manager (direct shortcut)
Block-PredefinedKey "Ctrl+Esc"             # Start menu (keyboard alternative)

# -- Task / window switching --------------------------------------------------
Block-PredefinedKey "Alt+Tab"              # Switch between open windows
Block-PredefinedKey "Alt+Shift+Tab"        # Switch windows (reverse)
Block-PredefinedKey "Alt+F4"               # Close active window / shut down prompt

# -- Accessibility shortcuts (can be triggered accidentally on a touchscreen) --
Block-PredefinedKey "Shift+Ctrl+Esc"       # Sticky Keys prompt
# Block-PredefinedKey "Shift"              # Held Shift key (Sticky Keys trigger)
#   ^ uncomment above only if users have no need to type capital letters via Shift

# -- Function / system keys ---------------------------------------------------
# Block-PredefinedKey "F1"                 # Help (app-specific; uncomment if needed)
# Block-PredefinedKey "F11"                # Full-screen toggle in browsers

# -- Custom combos (examples – uncomment or add as needed) --------------------
# Block-CustomKey "Ctrl+Alt+T"             # Terminal shortcut on some systems
# Block-CustomKey "Ctrl+Alt+Arrow"         # Screen rotation on Intel graphics

# ==============================================================================
#  STATUS REPORT
# ==============================================================================
Write-Host ""
Write-Host "Current Keyboard Filter state:"
Write-Host "-------------------------------"
Get-WMIObject -Namespace $NAMESPACE -Class WEKF_PredefinedKey |
    Where-Object { $_.Enabled -eq 1 } |
    Sort-Object Id |
    ForEach-Object { Write-Host "  BLOCKED: $($_.Id)" }

$customKeys = Get-WMIObject -Namespace $NAMESPACE -Class WEKF_CustomKey |
    Where-Object { $_.Enabled -eq 1 }
if ($customKeys) {
    $customKeys | Sort-Object Id | ForEach-Object {
        Write-Host "  BLOCKED (custom): $($_.Id)"
    }
}

Write-Host ""
Write-Host "Done. Changes take effect immediately (no reboot required)."
Write-Host "To make changes permanent in the golden image, capture the WIM after running this script."
Write-Host ""
