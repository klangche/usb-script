# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows Launcher
# =============================================================================
# Launches the USB diagnostic tool on Windows.
# Detects bash (Git Bash/WSL) → prefers universal script; otherwise uses native PS.
# Supports optional -Deep switch for real-time ETW-based USB signal monitoring.
# =============================================================================

param(
    [switch]$Deep
)

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Windows Launcher" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "Zero-footprint mode: Everything runs in memory" -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check for bash availability
$hasBash = Get-Command bash -ErrorAction SilentlyContinue

if ($hasBash) {
    Write-Host "Bash detected - using universal script for maximum detail" -ForegroundColor Green
    Write-Host "(Script loads directly in memory via pipe, nothing saved)" -ForegroundColor Gray
    Write-Host ""
    
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh | bash"
    } else {
        $scriptContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh"
        $scriptContent | bash
    }
}
else {
    Write-Host "No bash detected - running native PowerShell mode" -ForegroundColor Yellow
    Write-Host ""
    
    $psScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
    Invoke-Expression $psScript
}

# ─────────────────────────────────────────────────────────────────────────────
# DEEP ANALYTICS MODE (only runs if -Deep is specified)
# ─────────────────────────────────────────────────────────────────────────────
if ($Deep) {
    function Test-Admin {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Start-USBDeepAnalysis {
        if (-not (Test-Admin)) {
            Write-Host ""
            Write-Host "Deep analysis requires Administrator privileges." -ForegroundColor Red
            Write-Host "Restart PowerShell as Administrator and run again with -Deep" -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host "===================== DEEP USB ANALYTICS =====================" -ForegroundColor Cyan
        Write-Host "Real-time USB signal stability monitoring active" -ForegroundColor Gray
        Write-Host "Detecting CRC errors, resets, timeouts, power faults, re-handshakes..." -ForegroundColor Gray
        Write-Host "Press CTRL+C to stop" -ForegroundColor Yellow
        Write-Host ""

        # ───────────────────────────────────────────────
        # Show current USB devices snapshot for reference
        # ───────────────────────────────────────────────
        Write-Host "Current connected USB devices (reference snapshot):" -ForegroundColor Cyan
        Write-Host "-----------------------------------------------------" -ForegroundColor DarkGray

        $devices = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' } |
            Select-Object @{Name='Name';Expression={if($_.FriendlyName){$_.FriendlyName}else{$_.Name}}},
                          @{Name='Status';Expression={$_.Status}},
                          InstanceId

        if ($devices.Count -eq 0) {
            Write-Host "  (No USB devices currently detected)" -ForegroundColor Yellow
        } else {
            $devices | Format-Table -AutoSize | Out-Host
        }
        Write-Host ""

        # ───────────────────────────────────────────────
        # Event counters
        # ───────────────────────────────────────────────
        $eventCounts = @{
            CRC             = 0
            Timeout         = 0
            Reset           = 0
            Overcurrent     = 0
            EnumerationFail = 0
            Bandwidth       = 0
            ReHandshake     = 0
            Other           = 0
        }

        $trace = "LK_USB_TRACE"

        # Clean previous sessions silently
        logman stop $trace -ets 2>$null | Out-Null
        logman delete $trace 2>$null | Out-Null

        # Start high-verbosity USB ETW trace
        logman start $trace `
            -p Microsoft-Windows-USB-USBPORT 0xFFFFFFFF 5 `
            -p Microsoft-Windows-USB-UCX 0xFFFFFFFF 5 `
            -p Microsoft-Windows-USB-HUB3 0xFFFFFFFF 5 `
            -ets | Out-Null

        Write-Host "Deep telemetry engine started → waiting for events..." -ForegroundColor Green
        Write-Host ""

        $script:StartTime = Get-Date

        try {
            Get-WinEvent -LogName "Microsoft-Windows-USB-USBPORT/Operational" -MaxEvents 0 -Wait -ErrorAction SilentlyContinue |
            ForEach-Object {

                $msg   = $_.Message
                $evId  = $_.Id
                $time  = $_.TimeCreated.ToString("HH:mm:ss.fff")
                $etype = ""
                $color = "Red"

                if     ($msg -match "(?i)crc|checksum|error")                  { $etype = "CRC / Signal Integrity";        $eventCounts.CRC++;             $color = "Yellow" }
                elseif ($msg -match "(?i)timeout|transfer timeout")            { $etype = "Transfer Timeout";               $eventCounts.Timeout++;         $color = "Yellow" }
                elseif ($msg -match "(?i)reset|link reset|port reset")         { $etype = "Device / Link Reset";             $eventCounts.Reset++;           $color = "Magenta" }
                elseif ($msg -match "(?i)overcurrent|power fault")             { $etype = "Power / Overcurrent Fault";      $eventCounts.Overcurrent++;     $color = "Magenta" }
                elseif ($msg -match "(?i)enumeration|enum failed|enum retry")  { $etype = "Enumeration Failure";            $eventCounts.EnumerationFail++; $color = "Red" }
                elseif ($msg -match "(?i)bandwidth|allocation")                { $etype = "Bandwidth Allocation Issue";     $eventCounts.Bandwidth++;       $color = "Yellow" }
                elseif ($msg -match "(?i)surprise removed|missing on bus|device gone|re-enumerat|disconnect.*connect|reset.*(connect|enumerate|appear)") {
                    $etype = "Re-Handshake / Surprise Removal";   $eventCounts.ReHandshake++;   $color = "Yellow"
                }
                else                                                   { $etype = "Other USB Event";                 $eventCounts.Other++;           $color = "Gray"  }

                # Skip noise / uninteresting events
                if ($etype -eq "Other USB Event") { return }

                Write-Host "[$time] $etype" -ForegroundColor $color
                Write-Host "  Event ID : $evId" -ForegroundColor DarkGray
                Write-Host "  Message  : $msg" -ForegroundColor Gray
                Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
            }
        }
        finally {
            Write-Host ""
            Write-Host "Stopping telemetry engine..." -ForegroundColor Yellow
            logman stop $trace -ets 2>$null | Out-Null
            logman delete $trace 2>$null | Out-Null

            # ───────────────────────────────────────────────
            # Final summary
            # ───────────────────────────────────────────────
            $elapsed = "{0:mm}:{0:ss}" -f ((Get-Date) - $script:StartTime)

            Write-Host ""
            Write-Host "Deep monitoring summary ($elapsed)" -ForegroundColor Cyan
            Write-Host "───────────────────────────────────────────────" -ForegroundColor DarkGray

            $eventCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
                if ($_.Value -gt 0) {
                    $color = if ($_.Value -ge 5) { "Red" } elseif ($_.Value -ge 2) { "Yellow" } else { "Green" }
                    Write-Host ("  {0,-18} : {1,2}" -f $_.Key, $_.Value) -ForegroundColor $color
                }
            }

            if (($eventCounts.Values | Measure-Object -Sum).Sum -eq 0) {
                Write-Host "  No instability events detected during monitoring." -ForegroundColor Green
            } else {
                Write-Host ""
                Write-Host "Most frequent issues:" -ForegroundColor Cyan
                $top = $eventCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2
                foreach ($item in $top) {
                    if ($item.Value -gt 0) {
                        Write-Host "  • $($item.Key) ($($item.Value) times)" -ForegroundColor Yellow
                    }
                }

                # Practical warning for high reset / re-handshake counts
                if ($eventCounts.ReHandshake -ge 5 -or $eventCounts.Reset -ge 8) {
                    Write-Host ""
                    Write-Host "Warning: High number of resets / re-handshakes detected!" -ForegroundColor Red
                    Write-Host " → Possible causes: overheating cable/hub (AOC/active extender), bad power delivery, marginal signal" -ForegroundColor Yellow
                    Write-Host " → Try: shorter cable, powered hub, fewer chained devices, better ventilation" -ForegroundColor Yellow
                }
            }

            Write-Host ""
            Write-Host "Deep analysis stopped cleanly." -ForegroundColor Green
        }
    }

    # Run deep mode
    Start-USBDeepAnalysis
}
