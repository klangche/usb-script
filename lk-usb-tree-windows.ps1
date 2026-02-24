# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows Launcher (with integrated Deep Analytics)
# =============================================================================
# - Runs tree visualization first
# - Then offers deep monitoring (simple polling or advanced ETW)
# - Handles admin elevation automatically when needed
# - Zero-footprint where possible
# =============================================================================

param(
    [switch]$Deep,                  # Optional: start directly in deep mode
    [switch]$ETW                    # Internal: used during relaunch for ETW mode
)

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Test if running as Administrator
# ─────────────────────────────────────────────────────────────────────────────
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isAdmin = Test-Admin

# ─────────────────────────────────────────────────────────────────────────────
# Run the main tree visualization first (always)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Running USB Tree Visualization..." -ForegroundColor Cyan
$treeScriptUrl = "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
try {
    $treeContent = Invoke-RestMethod -Uri $treeScriptUrl
    Invoke-Expression $treeContent
}
catch {
    Write-Host "Failed to load tree script: $_" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# Deep Analytics Selection (only if -Deep or after tree)
# ─────────────────────────────────────────────────────────────────────────────
if ($Deep -or $ETW) {
    if ($ETW) {
        # Relaunched for ETW — run advanced mode directly
        Write-Host ""
        Write-Host "Running ADVANCED ETW Deep Analytics (requires admin)" -ForegroundColor Cyan
        Start-AdvancedETWAnalysis
    }
    else {
        # Normal deep start — let user choose mode
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "DEEP ANALYTICS OPTIONS" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "1. Simple monitoring (connect/disconnect detection) - no admin needed"
        Write-Host "2. Advanced monitoring (CRC, resets, overcurrent, etc.) - requires admin"
        Write-Host "==============================================================================" -ForegroundColor Cyan

        $choice = Read-Host "Choose mode (1 or 2) or press Enter to skip"

        if ($choice -eq "1") {
            Write-Host "Starting SIMPLE deep monitoring..." -ForegroundColor Green
            Start-SimplePollingAnalysis
        }
        elseif ($choice -eq "2") {
            if ($isAdmin) {
                Write-Host "Starting ADVANCED ETW monitoring..." -ForegroundColor Green
                Start-AdvancedETWAnalysis
            }
            else {
                Write-Host "Advanced mode requires admin rights. Relaunching as admin..." -ForegroundColor Yellow
                $scriptPath = $MyInvocation.MyCommand.Path
                if (-not $scriptPath) {
                    $scriptPath = "$env:TEMP\usb-deep-temp.ps1"
                    $selfContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-windows.ps1"
                    $selfContent | Out-File -FilePath $scriptPath -Encoding UTF8
                }
                Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Deep -ETW" -Verb RunAs
                exit
            }
        }
        else {
            Write-Host "Deep analytics skipped." -ForegroundColor Gray
        }
    }
}
else {
    # Normal run — offer deep after tree
    $wantDeep = Read-Host "Run Deep Analytics now? (y/n)"
    if ($wantDeep -match '^[Yy]') {
        # Relaunch self with -Deep to enter the selection flow
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        if ($scriptPath) {
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Deep" -Verb RunAs:$isAdmin
        }
        else {
            Write-Host "Cannot relaunch — run script from file instead of direct irm | iex" -ForegroundColor Yellow
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SIMPLE POLLING DEEP MODE (old style, no admin)
# ─────────────────────────────────────────────────────────────────────────────
function Start-SimplePollingAnalysis {
    $deepLog = "$env:TEMP\usb-deep-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $script:StartTime = Get-Date
    $script:IsStable = $true
    $script:Rehandshakes = 0

    $initialDevices = @{}
    Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' } | ForEach-Object {
        $name = if ($_.FriendlyName) { $_.FriendlyName } else { $_.Name }
        $initialDevices[$_.InstanceId] = $name
    }

    function Write-Event { param($Type, $Message, $Device)
        $time = Get-Date -Format "HH:mm:ss.fff"
        "[$time] [$Type] $Message $Device" | Add-Content -Path $deepLog
    }

    Write-Event -Type "INFO" -Message "Simple Deep Analytics started" -Device ""

    try {
        $previousDevices = $initialDevices.Clone()
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            $current = Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' }
            $currentMap = @{}
            foreach ($dev in $current) {
                $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
                $currentMap[$dev.InstanceId] = $name
            }

            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-Event -Type "REHANDSHAKE" -Message "Device disconnected" -Device $previousDevices[$id]
                    $script:Rehandshakes++
                    $script:IsStable = $false
                }
            }

            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-Event -Type "INFO" -Message "Device connected" -Device $currentMap[$id]
                }
            }

            $previousDevices = $currentMap.Clone()

            Clear-Host
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }

            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "DEEP ANALYTICS (Simple) - $([string]::Format('{0:hh\:mm\:ss}', $elapsed)) elapsed" -ForegroundColor Magenta
            Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "STATUS: $statusText" -ForegroundColor $statusColor
            Write-Host "Re-handshakes: $($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
            Write-Host ""

            Start-Sleep -Seconds 1
        }
    }
    finally {
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host ""
        Write-Host "DEEP ANALYTICS COMPLETE" -ForegroundColor Magenta
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))"
        Write-Host "Final status: $(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
        Write-Host "Re-handshakes: $script:Rehandshakes"
        Write-Host "Log saved: $deepLog" -ForegroundColor Gray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ADVANCED ETW DEEP MODE (requires admin)
# ─────────────────────────────────────────────────────────────────────────────
function Start-AdvancedETWAnalysis {
    # (Paste the full ETW function from previous message here — the one with $eventCounts, ReHandshake, device snapshot, etc.)
    # For brevity I'm not repeating the 100+ lines here, but insert the entire Start-AdvancedETWAnalysis function body
    # from the last complete version I provided (with counters, regex for ReHandshake, warning on high resets, etc.)
    # Example start:
    Write-Host "===================== ADVANCED ETW USB ANALYTICS =====================" -ForegroundColor Cyan
    # ... rest of the function ...
}

Write-Host ""
Write-Host "Done. Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
