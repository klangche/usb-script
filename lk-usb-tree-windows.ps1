# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows Launcher
# =============================================================================
# - Always runs tree visualization + HTML report first
# - After that, asks for deep analytics (y/n)
# - No admin → simple polling only (re-handshakes)
# - Admin → advanced ETW only (CRC/reset/overcurrent + re-handshakes)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Windows Edition" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# Check elevation status
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Running as Administrator → advanced deep analytics available" -ForegroundColor Green
} else {
    Write-Host "Running without admin rights → basic deep analytics only (if selected)" -ForegroundColor Yellow
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Run tree visualization (always first)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Running USB tree visualization..." -ForegroundColor Gray

$treeUrl = "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
try {
    $treeContent = Invoke-RestMethod -Uri $treeUrl
    Invoke-Expression $treeContent
} catch {
    Write-Host "Tree script failed: $_" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# Prompt for deep analytics AFTER tree + HTML
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
$wantDeep = Read-Host "Run deep analytics / stability monitoring now? (y/n)"

if ($wantDeep -notmatch '^[Yy]') {
    Write-Host "Deep analytics skipped." -ForegroundColor Gray
} else {
    if (-not $isAdmin) {
        Write-Host "Starting BASIC deep monitoring (re-handshakes / disconnects)..." -ForegroundColor Green
        Start-SimpleDeepPolling
    } else {
        Write-Host "Starting ADVANCED deep monitoring (CRC, resets, overcurrent, re-handshakes...)" -ForegroundColor Green
        Start-AdvancedETWDeep
    }
}

Write-Host ""
Write-Host "Done. Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# ─────────────────────────────────────────────────────────────────────────────
# BASIC / OLD DEEP MODE — no admin needed
# ─────────────────────────────────────────────────────────────────────────────
function Start-SimpleDeepPolling {
    $logFile = "$env:TEMP\usb-deep-simple-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $startTime = Get-Date
    $isStable = $true
    $rehandshakes = 0

    $initial = @{}
    Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' } | ForEach-Object {
        $name = if ($_.FriendlyName) { $_.FriendlyName } else { $_.Name }
        $initial[$_.InstanceId] = $name
    }

    function Log-Event($Type, $Msg, $Dev = "") {
        $t = Get-Date -Format "HH:mm:ss.fff"
        "[$t] [$Type] $Msg $Dev" | Add-Content $logFile
    }

    Log-Event "INFO" "Simple deep analytics started"

    try {
        $prev = $initial.Clone()
        while ($true) {
            $elapsed = (Get-Date) - $startTime
            $currDevs = Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' }
            $curr = @{}
            foreach ($d in $currDevs) {
                $name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }
                $curr[$d.InstanceId] = $name
            }

            foreach ($id in $prev.Keys) {
                if (-not $curr.ContainsKey($id)) {
                    Log-Event "REHANDSHAKE" "Device disconnected" $prev[$id]
                    $rehandshakes++
                    $isStable = $false
                }
            }

            foreach ($id in $curr.Keys) {
                if (-not $prev.ContainsKey($id)) {
                    Log-Event "INFO" "Device connected" $curr[$id]
                }
            }

            $prev = $curr.Clone()

            Clear-Host
            $color = if ($isStable) { "Green" } else { "Magenta" }
            $status = if ($isStable) { "STABLE" } else { "UNSTABLE" }

            Write-Host "DEEP ANALYTICS (Basic) - $(('{0:hh\:mm\:ss}' -f $elapsed)) elapsed" -ForegroundColor Magenta
            Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host "Status: $status" -ForegroundColor $color
            Write-Host "Re-handshakes: $rehandshakes" -ForegroundColor $(if ($rehandshakes -gt 0) {"Yellow"} else {"Gray"})
            Write-Host ""

            Start-Sleep -Seconds 1
        }
    }
    finally {
        $total = (Get-Date) - $startTime
        Write-Host ""
        Write-Host "Basic deep analytics stopped" -ForegroundColor Magenta
        Write-Host "Duration: $('{0:hh\:mm\:ss}' -f $total)"
        Write-Host "Final status: $(if ($isStable) {'STABLE'} else {'UNSTABLE'})" -ForegroundColor $(if ($isStable) {"Green"} else {"Magenta"})
        Write-Host "Re-handshakes: $rehandshakes"
        Write-Host "Log saved to: $logFile" -ForegroundColor Gray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ADVANCED / NEW DEEP MODE — admin only
# ─────────────────────────────────────────────────────────────────────────────
function Start-AdvancedETWDeep {
    # Full ETW version from earlier (paste the complete function here)
    # Example abbreviated start — replace with your latest full ETW code
    if (-not $isAdmin) { Write-Host "Admin required for ETW" -ForegroundColor Red; return }

    $logFile = "$env:TEMP\usb-deep-etw-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $traceName = "USB-DEEP-TRACE"

    Write-Host "Starting advanced ETW monitoring..." -ForegroundColor Cyan
    Write-Host "Providers: USBPORT, UCX, HUB3" -ForegroundColor Gray

    # Cleanup old trace
    logman stop $traceName -ets 2>$null | Out-Null
    logman delete $traceName 2>$null | Out-Null

    # Start trace
    logman create trace $traceName -o "$env:TEMP\usb-etw.etl" -ets
    logman update trace $traceName -p Microsoft-Windows-USB-USBPORT 0xFFFFFFFF 5 -ets
    logman update trace $traceName -p Microsoft-Windows-USB-UCX 0xFFFFFFFF 5 -ets
    logman update trace $traceName -p Microsoft-Windows-USB-HUB3 0xFFFFFFFF 5 -ets
    logman start $traceName -ets

    Write-Host "ETW trace active. Monitoring events..." -ForegroundColor Green

    $counts = @{CRC=0; Timeout=0; Reset=0; Overcurrent=0; EnumFail=0; Bandwidth=0; ReHandshake=0; Other=0}

    try {
        Get-WinEvent -LogName "Microsoft-Windows-USB-USBPORT/Operational" -MaxEvents 0 -Wait -ErrorAction SilentlyContinue | ForEach-Object {
            $msg = $_.Message
            $time = $_.TimeCreated.ToString("HH:mm:ss.fff")
            $etype = ""
            $col = "Gray"

            if ($msg -match "(?i)crc|checksum") { $etype = "CRC"; $counts.CRC++; $col = "Yellow" }
            elseif ($msg -match "(?i)timeout") { $etype = "Timeout"; $counts.Timeout++; $col = "Yellow" }
            elseif ($msg -match "(?i)reset|port reset") { $etype = "Reset"; $counts.Reset++; $col = "Magenta" }
            elseif ($msg -match "(?i)overcurrent") { $etype = "Overcurrent"; $counts.Overcurrent++; $col = "Magenta" }
            elseif ($msg -match "(?i)enumeration|enum failed") { $etype = "EnumFail"; $counts.EnumFail++; $col = "Red" }
            elseif ($msg -match "(?i)bandwidth") { $etype = "Bandwidth"; $counts.Bandwidth++; $col = "Yellow" }
            elseif ($msg -match "(?i)surprise|missing|re-enum|disconnect.*connect") { $etype = "ReHandshake"; $counts.ReHandshake++; $col = "Yellow" }
            else { $etype = "Other"; $counts.Other++; $col = "Gray" }

            if ($etype -eq "Other") { return }

            Write-Host "[$time] $etype" -ForegroundColor $col
            Write-Host "  $msg" -ForegroundColor Gray
            Write-Host "  ───────" -ForegroundColor DarkGray
        }
    }
    finally {
        logman stop $traceName -ets 2>$null | Out-Null
        logman delete $traceName 2>$null | Out-Null

        Write-Host ""
        Write-Host "Advanced ETW monitoring stopped" -ForegroundColor Cyan
        Write-Host "Summary:"
        $counts.GetEnumerator() | Sort-Object Value -Descending | Where-Object {$_.Value -gt 0} | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor $(if ($_.Value -ge 3) {"Red"} elseif ($_.Value -ge 1) {"Yellow"} else {"Green"})
        }
        if (($counts.Values | Measure-Object -Sum).Sum -eq 0) {
            Write-Host "  No errors detected during monitoring" -ForegroundColor Green
        }
        Write-Host "ETW trace file (for later analysis): $env:TEMP\usb-etw.etl" -ForegroundColor Gray
    }
}
