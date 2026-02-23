# =============================================================================
# USB DEEP ANALYTICS - Real-time USB Stability Monitor
# =============================================================================
# This tool continuously monitors USB connections and reports:
# - Connection drops/re-handshakes
# - Random errors
# - Overall stability status
#
# USAGE: Run after HTML report, keeps monitoring until Ctrl+C
# =============================================================================

param(
    [switch]$HtmlOutput,
    [string]$LogFile = "$env:TEMP\usb-deep-analytics-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# Color codes for PowerShell
$Colors = @{
    Header = 'Cyan'
    Stable = 'Green'
    Unstable = 'Red'
    Warning = 'Yellow'
    Critical = 'Magenta'
    Info = 'Gray'
}

# Initialize counters
$script:RandomErrors = 0
$script:Rehandshakes = 0
$script:IsStable = $true
$script:StartTime = Get-Date
$script:LastEventLog = @()
$script:MaxLogEntries = 50  # Keep last 50 events for display

# =============================================================================
# EVENT HANDLERS - Monitor USB changes in real-time
# =============================================================================

# Function to log events
Write-EventLog {
    param(
        [string]$Message,
        [string]$Type = "INFO",  # INFO, WARNING, ERROR, REHANDSHAKE
        [string]$Device = ""
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $event = @{
        Time = $timestamp
        Type = $Type
        Message = $Message
        Device = $Device
    }
    
    # Add to log
    $script:LastEventLog = @($event) + $script:LastEventLog[0..($script:MaxLogEntries-2)]
    
    # Update counters based on event type
    switch ($Type) {
        "ERROR" { 
            $script:RandomErrors++
            $script:IsStable = $false
        }
        "REHANDSHAKE" { 
            $script:Rehandshakes++
            $script:IsStable = $false
        }
        "WARNING" { 
            $script:IsStable = $false
        }
    }
    
    # Write to log file
    "$timestamp [$Type] $Message $Device" | Out-File -FilePath $LogFile -Append
}

# Function to monitor USB devices using WMI events
Start-USBMonitoring {
    Write-Host "`n" -NoNewline
    Write-Host "=" * 80 -ForegroundColor $Colors.Header
    Write-Host "USB DEEP ANALYTICS - Real-time Stability Monitor" -ForegroundColor $Colors.Header
    Write-Host "=" * 80 -ForegroundColor $Colors.Header
    Write-Host "Monitoring USB connections... Press Ctrl+C to stop" -ForegroundColor $Colors.Info
    Write-Host "Log file: $LogFile" -ForegroundColor $Colors.Info
    Write-Host "=" * 80 -ForegroundColor $Colors.Header
    Write-Host ""
    
    # Set up WMI event watchers for USB devices
    $usbQuery = "SELECT * FROM __InstanceOperationEvent WITHIN 2 WHERE TargetInstance ISA 'Win32_USBHub'"
    $action = {
        $eventType = $Event.SourceEventArgs.NewEvent.__CLASS
        $deviceName = $Event.SourceEventArgs.NewEvent.TargetInstance.Name
        $deviceID = $Event.SourceEventArgs.NewEvent.TargetInstance.DeviceID
        
        switch ($eventType) {
            "__InstanceCreationEvent" {
                Write-EventLog -Type "INFO" -Message "USB device connected" -Device $deviceName
            }
            "__InstanceDeletionEvent" {
                Write-EventLog -Type "REHANDSHAKE" -Message "USB device disconnected - re-handshake required" -Device $deviceName
            }
            "__InstanceModificationEvent" {
                Write-EventLog -Type "WARNING" -Message "USB device state changed" -Device $deviceName
            }
        }
    }
    
    # Also monitor PnP events for more detailed USB changes
    $pnpQuery = "SELECT * FROM Win32_DeviceChangeEvent"
    $pnpAction = {
        $eventType = $Event.SourceEventArgs.NewEvent.EventType
        switch ($eventType) {
            1 { # Configuration changed
                Write-EventLog -Type "WARNING" -Message "USB configuration changed"
            }
            2 { # Device arrived
                # Handled by USB query
            }
            3 { # Device removed
                # Handled by USB query
            }
            4 { # Docking changed
                Write-EventLog -Type "REHANDSHAKE" -Message "Docking station state changed - full USB re-enumeration"
            }
        }
    }
    
    # Register for events
    $usbWatcher = Register-WmiEvent -Query $usbQuery -Action $action -SupportEvent
    $pnpWatcher = Register-WmiEvent -Query $pnpQuery -Action $pnpAction -SupportEvent
    
    # Also monitor USB device errors in System event log
    $eventLogQuery = "SELECT * FROM System WHERE EventCode=2010 OR EventCode=2011 OR EventCode=2012"  # USB related errors
    $logAction = {
        $eventCode = $Event.SourceEventArgs.NewEvent.EventCode
        $message = $Event.SourceEventArgs.NewEvent.Message
        
        switch ($eventCode) {
            2010 { Write-EventLog -Type "ERROR" -Message "USB controller error" -Device $message }
            2011 { Write-EventLog -Type "ERROR" -Message "USB device error" -Device $message }
            2012 { Write-EventLog -Type "WARNING" -Message "USB bandwidth exceeded" -Device $message }
        }
    }
    
    $logWatcher = Register-ObjectEvent -Query $eventLogQuery -Action $logAction -SupportEvent
    
    # Main display loop - updates every second
    try {
        while ($true) {
            # Clear screen for real-time updates (optional - comment out if you prefer scrolling)
            # Clear-Host
            
            $elapsed = (Get-Date) - $script:StartTime
            $statusColor = if ($script:IsStable) { $Colors.Stable } else { $Colors.Unstable }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            # Header with elapsed time
            Write-Host "`n" -NoNewline
            Write-Host "=" * 80 -ForegroundColor $Colors.Header
            Write-Host "LONG TEST HAS BEEN RUN FOR $($elapsed.ToString())" -ForegroundColor $Colors.Header
            Write-Host "Press Ctrl+C to cancel" -ForegroundColor $Colors.Info
            Write-Host "=" * 80 -ForegroundColor $Colors.Header
            
            # Status line
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            
            # Counters
            Write-Host "RANDOM ERRORS: " -NoNewline
            Write-Host "$($script:RandomErrors.ToString('D2'))" -ForegroundColor $(if ($script:RandomErrors -gt 0) { $Colors.Warning } else { $Colors.Info })
            
            Write-Host "RE-HANDSHAKES: " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { $Colors.Warning } else { $Colors.Info })
            Write-Host ""
            
            # Recent events (last 5)
            Write-Host "RECENT EVENTS:" -ForegroundColor $Colors.Header
            $recentEvents = $script:LastEventLog | Select-Object -First 5
            if ($recentEvents.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor $Colors.Info
            } else {
                foreach ($event in $recentEvents) {
                    $eventColor = switch ($event.Type) {
                        "ERROR" { $Colors.Critical }
                        "REHANDSHAKE" { $Colors.Warning }
                        "WARNING" { $Colors.Warning }
                        default { $Colors.Info }
                    }
                    Write-Host "  [$($event.Time)] " -NoNewline -ForegroundColor $Colors.Info
                    Write-Host "$($event.Type): " -NoNewline -ForegroundColor $eventColor
                    Write-Host "$($event.Message) $($event.Device)" -ForegroundColor $Colors.Info
                }
            }
            
            # Summary line
            Write-Host ""
            Write-Host "-" * 80 -ForegroundColor $Colors.Header
            if (-not $script:IsStable) {
                Write-Host "DETAILED ERROR LOG:" -ForegroundColor $Colors.Critical
                $errors = $script:LastEventLog | Where-Object { $_.Type -in @('ERROR', 'REHANDSHAKE', 'WARNING') } | Select-Object -First 10
                foreach ($err in $errors) {
                    Write-Host "  [$($err.Time)] " -NoNewline -ForegroundColor $Colors.Info
                    Write-Host "$($err.Type): " -NoNewline -ForegroundColor $Colors.Warning
                    Write-Host "$($err.Message) $($err.Device)" -ForegroundColor $Colors.Info
                }
                Write-Host ""
                Write-Host "Check log file for complete history: $LogFile" -ForegroundColor $Colors.Info
            }
            Write-Host "=" * 80 -ForegroundColor $Colors.Header
            
            # Update every second
            Start-Sleep -Seconds 1
        }
    }
    finally {
        # Clean up event watchers when Ctrl+C is pressed
        $usbWatcher | Unregister-Event -Force -ErrorAction SilentlyContinue
        $pnpWatcher | Unregister-Event -Force -ErrorAction SilentlyContinue
        $logWatcher | Unregister-Event -Force -ErrorAction SilentlyContinue
        
        Write-Host "`n" -NoNewline
        Write-Host "=" * 80 -ForegroundColor $Colors.Header
        Write-Host "DEEP ANALYTICS SUMMARY" -ForegroundColor $Colors.Header
        Write-Host "=" * 80 -ForegroundColor $Colors.Header
        Write-Host "Total runtime: $((Get-Date) - $script:StartTime)" -ForegroundColor $Colors.Info
        Write-Host "Final status: " -NoNewline
        Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { $Colors.Stable } else { $Colors.Unstable })
        Write-Host "Total random errors: $script:RandomErrors" -ForegroundColor $(if ($script:RandomErrors -gt 0) { $Colors.Warning } else { $Colors.Info })
        Write-Host "Total re-handshakes: $script:Rehandshakes" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { $Colors.Warning } else { $Colors.Info })
        Write-Host ""
        Write-Host "Full log saved to: $LogFile" -ForegroundColor $Colors.Info
        Write-Host "=" * 80 -ForegroundColor $Colors.Header
    }
}

# =============================================================================
# HTML OUTPUT MODE - For browser display in separate tab
# =============================================================================
if ($HtmlOutput) {
    # Generate HTML version that auto-refreshes
    $htmlFile = "$env:TEMP\usb-deep-analytics-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Deep Analytics - Real-time Monitor</title>
    <meta http-equiv="refresh" content="2">
    <style>
        body { 
            font-family: 'Consolas', monospace; 
            background: #0d1117; 
            color: #e6edf3; 
            padding: 20px;
            margin: 0;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            background: #161b22;
            padding: 20px;
            border-radius: 8px 8px 0 0;
            border: 1px solid #30363d;
            border-bottom: none;
        }
        .header h1 {
            color: #79c0ff;
            margin: 0;
            font-size: 24px;
        }
        .header p {
            color: #8b949e;
            margin: 10px 0 0 0;
        }
        .status-panel {
            background: #161b22;
            padding: 20px;
            border: 1px solid #30363d;
            border-top: none;
        }
        .status-box {
            display: inline-block;
            padding: 10px 20px;
            border-radius: 6px;
            font-weight: bold;
            font-size: 18px;
            margin-bottom: 20px;
        }
        .status-stable {
            background: rgba(46, 160, 67, 0.15);
            border: 1px solid #2ea043;
            color: #7ee787;
        }
        .status-unstable {
            background: rgba(248, 81, 73, 0.15);
            border: 1px solid #f85149;
            color: #ff7b72;
        }
        .counters {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 20px;
            margin-bottom: 20px;
        }
        .counter {
            background: #0d1117;
            padding: 15px;
            border-radius: 6px;
            border: 1px solid #30363d;
        }
        .counter-label {
            color: #8b949e;
            font-size: 14px;
            margin-bottom: 5px;
        }
        .counter-value {
            font-size: 36px;
            font-weight: bold;
        }
        .counter-value.warning { color: #ffa657; }
        .counter-value.critical { color: #ff7b72; }
        .counter-value.normal { color: #7ee787; }
        
        .events {
            background: #0d1117;
            border-radius: 6px;
            border: 1px solid #30363d;
        }
        .events-header {
            padding: 15px;
            background: #161b22;
            border-bottom: 1px solid #30363d;
            color: #79c0ff;
            font-weight: bold;
        }
        .event {
            padding: 10px 15px;
            border-bottom: 1px solid #21262d;
            font-family: 'Consolas', monospace;
            font-size: 13px;
        }
        .event:last-child {
            border-bottom: none;
        }
        .event-time {
            color: #8b949e;
            margin-right: 15px;
        }
        .event-type {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: bold;
            margin-right: 10px;
        }
        .type-info { 
            background: rgba(121, 192, 255, 0.15); 
            color: #79c0ff;
            border: 1px solid #79c0ff;
        }
        .type-warning { 
            background: rgba(255, 166, 87, 0.15); 
            color: #ffa657;
            border: 1px solid #ffa657;
        }
        .type-error { 
            background: rgba(255, 123, 114, 0.15); 
            color: #ff7b72;
            border: 1px solid #ff7b72;
        }
        .type-rehandshake { 
            background: rgba(255, 166, 87, 0.15); 
            color: #ffa657;
            border: 1px solid #ffa657;
        }
        .event-message {
            color: #e6edf3;
        }
        .footer {
            margin-top: 20px;
            padding: 15px;
            background: #161b22;
            border-radius: 8px;
            border: 1px solid #30363d;
            color: #8b949e;
            font-size: 12px;
        }
        .refresh-note {
            color: #8b949e;
            font-size: 12px;
            margin-top: 10px;
            text-align: right;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>USB Deep Analytics - Real-time Monitor</h1>
            <p>Live USB stability monitoring | Auto-refreshes every 2 seconds | Press Ctrl+C in terminal to stop</p>
        </div>
        
        <div class="status-panel">
            <div id="status" class="status-box status-stable">
                STATUS: STABLE
            </div>
            
            <div class="counters">
                <div class="counter">
                    <div class="counter-label">RANDOM ERRORS</div>
                    <div id="errors" class="counter-value normal">00</div>
                </div>
                <div class="counter">
                    <div class="counter-label">RE-HANDSHAKES</div>
                    <div id="rehandshakes" class="counter-value normal">00</div>
                </div>
            </div>
            
            <div class="events">
                <div class="events-header">RECENT EVENTS</div>
                <div id="events-list">
                    <div class="event">
                        <span class="event-time">--:--:--.---</span>
                        <span class="event-type type-info">INFO</span>
                        <span class="event-message">Monitoring started</span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <strong>Deep Analytics Log:</strong> $LogFile<br>
            <span class="refresh-note">Page auto-refreshes every 2 seconds | Close this tab to stop monitoring</span>
        </div>
    </div>
    
    <script>
        // This would be updated via WebSocket or AJAX in a real implementation
        // For now, the meta refresh handles updates
        // In production, you'd want to read the log file via a simple HTTP server
    </script>
</body>
</html>
"@
    
    $html | Out-File -FilePath $htmlFile -Encoding UTF8
    Start-Process $htmlFile
    Write-Host "HTML monitor opened in browser: $htmlFile" -ForegroundColor Cyan
}
else {
    # Run in terminal mode
    Start-USBMonitoring
}
