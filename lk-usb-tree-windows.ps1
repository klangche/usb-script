# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows Launcher (Final Merged Version)
# =============================================================================
# - Tree + HTML always first
# - After that: prompt for deep analytics (y/n)
# - No admin → basic/old polling (re-handshakes only)
# - Admin → advanced/new ETW (CRC, resets, overcurrent, re-handshakes + more)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Windows Edition" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "Running as Administrator → deeper analytics available" -ForegroundColor Green
} else {
    Write-Host "No admin rights → basic deep analytics only (if selected)" -ForegroundColor Yellow
}
Write-Host ""

# Run tree visualization + HTML (unchanged)
Write-Host "Running USB tree visualization..." -ForegroundColor Gray
try {
    $treeContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
    Invoke-Expression $treeContent
} catch {
    Write-Host "Tree script failed: $_" -ForegroundColor Red
}

# Prompt after tree/HTML
Write-Host ""
$wantDeep = Read-Host "Run deep analytics / stability monitoring? (y/n)"

if ($wantDeep -notmatch '^[Yy]') {
    Write-Host "Deep analytics skipped." -ForegroundColor Gray
} else {
    if (-not $isAdmin) {
        Write-Host "`nStarting BASIC deep analytics (re-handshakes / disconnects only)..." -ForegroundColor Green
        Start-BasicDeepPolling
    } else {
        Write-Host "`nStarting DEEPER analytics (CRC, resets, overcurrent, re-handshakes + more)..." -ForegroundColor Green
        Start-DeeperETWAnalytics
    }
}

Write-Host ""
Write-Host "Done. Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# ─────────────────────────────────────────────────────────────────────────────
# BASIC / OLD MODE — no admin required
# ─────────────────────────────────────────────────────────────────────────────
function Start-BasicDeepPolling {
    $log = "$env:TEMP\usb-deep-basic-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $start = Get-Date
    $stable = $true
    $rehands = 0

    $initDevs = @{}
    Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | ForEach-Object {
        $name = if ($_.FriendlyName) {$_.FriendlyName} else {$_.Name}
        $initDevs[$_.InstanceId] = $name
    }

    function Log($Type, $Msg, $Dev="") {
        $t = Get-Date -Format "HH:mm:ss.fff"
        "[$t] [$Type] $Msg $Dev" | Add-Content $log
    }

    Log "INFO" "Basic deep started"

    try {
        $prev = $initDevs.Clone()
        while ($true) {
            $elap = (Get-Date) - $start
            $currDevs = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'}
            $curr = @{}
            foreach ($d in $currDevs) {
                $name = if ($d.FriendlyName) {$d.FriendlyName} else {$d.Name}
                $curr[$d.InstanceId] = $name
            }

            foreach ($id in $prev.Keys) {
                if (!$curr.ContainsKey($id)) {
                    Log "REHANDSHAKE" "Disconnected" $prev[$id]
                    $rehands++
                    $stable = $false
                }
            }
            foreach ($id in $curr.Keys) {
                if (!$prev.ContainsKey($id)) {
                    Log "INFO" "Connected" $curr[$id]
                }
            }
            $prev = $curr.Clone()

            Clear-Host
            $col = if ($stable) {"Green"} else {"Magenta"}
            $stat = if ($stable) {"STABLE"} else {"UNSTABLE"}

            Write-Host "DEEP ANALYTICS (Basic) - $('{0:hh\:mm\:ss}' -f $elap)" -ForegroundColor Magenta
            Write-Host "Press Ctrl+C to stop"
            Write-Host "Status: $stat" -ForegroundColor $col
            Write-Host "Re-handshakes: $rehands" -ForegroundColor $(if ($rehands -gt 0){"Yellow"} else {"Gray"})
            Start-Sleep -Seconds 1
        }
    } finally {
        $tot = (Get-Date) - $start
        Write-Host "`nBasic deep stopped"
        Write-Host "Duration: $('{0:hh\:mm\:ss}' -f $tot)"
        Write-Host "Status: $(if ($stable){'STABLE'}else{'UNSTABLE'})" -ForegroundColor $(if ($stable){"Green"}else{"Magenta"})
        Write-Host "Re-handshakes: $rehands"
        Write-Host "Log: $log" -ForegroundColor Gray
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# DEEPER / NEW MODE — admin only (ETW-based)
# ─────────────────────────────────────────────────────────────────────────────
function Start-DeeperETWAnalytics {
    if (-not $isAdmin) { Write-Host "Admin required for deeper mode" -ForegroundColor Red; return }

    $trace = "USB-DEEP-TRACE"
    $etlFile = "$env:TEMP\usb-etw-$(Get-Date -Format 'yyyyMMdd-HHmmss').etl"
    $start = Get-Date

    $counts = @{CRC=0; Timeout=0; Reset=0; Overcurrent=0; EnumFail=0; Bandwidth=0; ReHandshake=0; Other=0}

    # Cleanup
    logman stop $trace -ets 2>$null | Out-Null
    logman delete $trace 2>$null | Out-Null

    # Start ETW trace
    logman start $trace -o $etlFile -ets
    logman update $trace -p Microsoft-Windows-USB-USBPORT 0xFFFFFFFF 5 -ets
    logman update $trace -p Microsoft-Windows-USB-UCX 0xFFFFFFFF 5 -ets
    logman update $trace -p Microsoft-Windows-USB-HUB3 0xFFFFFFFF 5 -ets

    Write-Host "ETW trace running. Waiting for events..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow

    try {
        Get-WinEvent -LogName "Microsoft-Windows-USB-USBPORT/Operational" -MaxEvents 0 -Wait -ErrorAction SilentlyContinue | ForEach-Object {
            $msg = $_.Message
            $time = $_.TimeCreated.ToString("HH:mm:ss.fff")
            $etype = ""
            $col = "Gray"

            if ($msg -match "(?i)crc|checksum|error") { $etype = "CRC / Signal"; $counts.CRC++; $col = "Yellow" }
            elseif ($msg -match "(?i)timeout") { $etype = "Timeout"; $counts.Timeout++; $col = "Yellow" }
            elseif ($msg -match "(?i)reset|port reset") { $etype = "Reset"; $counts.Reset++; $col = "Magenta" }
            elseif ($msg -match "(?i)overcurrent") { $etype = "Overcurrent"; $counts.Overcurrent++; $col = "Magenta" }
            elseif ($msg -match "(?i)enumeration|enum failed") { $etype = "Enum Fail"; $counts.EnumFail++; $col = "Red" }
            elseif ($msg -match "(?i)bandwidth") { $etype = "Bandwidth"; $counts.Bandwidth++; $col = "Yellow" }
            elseif ($msg -match "(?i)surprise|missing|re-enum|disconnect.*connect") { $etype = "ReHandshake"; $counts.ReHandshake++; $col = "Yellow" }
            else { $etype = "Other"; $counts.Other++ }

            if ($etype -eq "Other") { return }

            Write-Host "[$time] $etype" -ForegroundColor $col
            Write-Host "  $msg" -ForegroundColor Gray
            Write-Host ""
        }
    } finally {
        logman stop $trace -ets 2>$null | Out-Null
        logman delete $trace 2>$null | Out-Null

        $elap = (Get-Date) - $start
        Write-Host ""
        Write-Host "Deeper analytics stopped ($('{0:mm}:{0:ss}' -f $elap))" -ForegroundColor Cyan
        Write-Host "Summary:"
        $counts.GetEnumerator() | Sort-Object Value -Descending | Where-Object {$_.Value -gt 0} | ForEach-Object {
            $c = if ($_.Value -ge 5) {"Red"} elseif ($_.Value -ge 1) {"Yellow"} else {"Green"}
            Write-Host "  $($_.Key.PadRight(12)) : $($_.Value)" -ForegroundColor $c
        }
        if (($counts.Values | Measure-Object -Sum).Sum -eq 0) {
            Write-Host "  No issues detected" -ForegroundColor Green
        } else {
            if ($counts.ReHandshake -ge 5 -or $counts.Reset -ge 5) {
                Write-Host "Warning: High resets/re-handshakes → check cables, power, heat (AOC/hub?)" -ForegroundColor Red
            }
        }
        Write-Host "ETL trace saved: $etlFile (open in Event Viewer or WPA)" -ForegroundColor Gray
    }
}
