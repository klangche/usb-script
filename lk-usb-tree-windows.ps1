# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# - Runs tree visualization + HTML report
# - After that, prompts for deep analytics (y/n)
# - No admin → basic/old polling mode (re-handshakes only)
# - Admin → deeper/new ETW mode (CRC, resets, overcurrent, re-handshakes + more)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Admin check + smart handling (prompt if not elevated for full detail)
# ─────────────────────────────────────────────────────────────────────────────
$originalIsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isAdmin = $originalIsAdmin  # Track current admin status

if (-not $isAdmin) {
    $adminChoice = Read-Host "Run with admin for maximum detail (full tree + deeper analytics)? (y/n)"
    if ($adminChoice -match '^[Yy]') {
        Write-Host "Relaunching as admin..." -ForegroundColor Yellow
        
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = "$env:TEMP\usb-tree-temp.ps1"
            $selfContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
            $selfContent | Out-File -FilePath $scriptPath -Encoding UTF8
        }
        
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit
    } else {
        Write-Host "Running without admin (basic tree + basic deep if selected)" -ForegroundColor Yellow
    }
} else {
    Write-Host "✓ Running with admin privileges → full deep analytics available" -ForegroundColor Green
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# USB enumeration and tree building (your existing code)
# ─────────────────────────────────────────────────────────────────────────────
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

Write-Host "Enumerating USB devices..." -ForegroundColor Gray

$allDevices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, FriendlyName, Name, Class, @{n='IsHub';e={
    ($_.FriendlyName -like "*hub*") -or ($_.Name -like "*hub*") -or ($_.Class -eq "USBHub") -or ($_.InstanceId -like "*HUB*")
}}

if ($allDevices.Count -eq 0) {
    Write-Host "No USB devices found." -ForegroundColor Yellow
    exit
}

$devices = $allDevices | Where-Object { -not $_.IsHub }
$hubs = $allDevices | Where-Object { $_.IsHub }

Write-Host "Found $($devices.Count) devices and $($hubs.Count) hubs" -ForegroundColor Gray

# Build map for hierarchy
$map = @{}
foreach ($d in $allDevices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ 
            Name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }
            Parent = $parent
            Children = @()
            InstanceId = $d.InstanceId
            IsHub = $d.IsHub
        }
    } catch {
        $map[$d.InstanceId] = @{ 
            Name = if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }
            Parent = $null
            Children = @()
            InstanceId = $d.InstanceId
            IsHub = $d.IsHub
        }
    }
}

# Build hierarchy
$roots = @()
foreach ($id in $map.Keys) {
    $node = $map[$id]
    if (-not $node.Parent) {
        $roots += $id
    } else {
        foreach ($parentId in $map.Keys) {
            if ($map[$parentId].Name -like "*$($node.Parent)*" -or $map[$parentId].InstanceId -like "*$($node.Parent)*") {
                $map[$parentId].Children += $id
                break
            }
        }
    }
}

# Generate tree
$treeOutput = ""
$maxHops = 0

function Print-Tree {
    param($id, $level, $prefix, $isLast)
    
    $node = $map[$id]
    if (-not $node) { return }
    
    $branch = if ($level -eq 0) { "├── " } else { $prefix + $(if ($isLast) { "└── " } else { "├── " }) }
    
    $displayName = if ($node.IsHub) { "$($node.Name) [HUB]" } else { $node.Name }
    $script:treeOutput += "$branch$displayName ← $level hops`n"
    $script:maxHops = [Math]::Max($script:maxHops, $level)
    
    $newPrefix = $prefix + $(if ($isLast) { "    " } else { "│   " })
    $children = $node.Children
    
    for ($i = 0; $i -lt $children.Count; $i++) {
        Print-Tree -id $children[$i] -level ($level + 1) -prefix $newPrefix -isLast ($i -eq $children.Count - 1)
    }
}

foreach ($root in $roots) {
    Print-Tree -id $root -level 0 -prefix "" -isLast $true
}

$numTiers = $maxHops + 1
$totalHubs = $hubs.Count
$totalDevices = $devices.Count
$stabilityScore = [Math]::Max(1, 9 - $maxHops)

# Platform stability table
$platforms = @{
    "Windows"                  = @{rec=5; max=7}
    "Linux"                    = @{rec=4; max=6}
    "Mac Intel"                = @{rec=5; max=7}
    "Mac Apple Silicon"        = @{rec=3; max=5}
    "iPad USB-C (M-series)"    = @{rec=2; max=4}
    "iPhone USB-C"             = @{rec=2; max=4}
    "Android Phone (Qualcomm)" = @{rec=3; max=5}
    "Android Tablet (Exynos)"  = @{rec=2; max=4}
}

$statusLines = @()
foreach ($plat in $platforms.Keys) {
    $rec = $platforms[$plat].rec
    $max = $platforms[$plat].max
    $status = if ($numTiers -le $rec) { "STABLE" } 
              elseif ($numTiers -le $max) { "POTENTIALLY UNSTABLE" } 
              else { "NOT STABLE" }
    $statusLines += [PSCustomObject]@{ Platform = $plat; Status = $status }
}

$order = @("Windows", "Linux", "Mac Intel", "Mac Apple Silicon", "iPad USB-C (M-series)", "iPhone USB-C", "Android Phone (Qualcomm)", "Android Tablet (Exynos)")
$statusLines = $statusLines | Sort-Object { $order.IndexOf($_.Platform) }

$maxPlatLen = ($statusLines.Platform | Measure-Object Length -Maximum).Maximum
$statusSummaryTerminal = ""
foreach ($line in $statusLines) {
    $pad = " " * ($maxPlatLen - $line.Platform.Length + 4)
    $statusSummaryTerminal += "$($line.Platform)$pad$($line.Status)`n"
}

$hostStatus = ($statusLines | Where-Object { $_.Platform -eq "Windows" }).Status
$hostColor = if ($hostStatus -eq "STABLE") { "Green" } elseif ($hostStatus -eq "POTENTIALLY UNSTABLE") { "Yellow" } else { "Magenta" }

# Console output
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host $treeOutput
Write-Host ""
Write-Host "Furthest jumps: $maxHops" -ForegroundColor Gray
Write-Host "Number of tiers: $numTiers" -ForegroundColor Gray
Write-Host "Total devices: $totalDevices" -ForegroundColor Gray
Write-Host "Total hubs: $totalHubs" -ForegroundColor Gray
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "STABILITY PER PLATFORM (based on $maxHops hops)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host $statusSummaryTerminal
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "HOST SUMMARY" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Host status: " -NoNewline
Write-Host "$hostStatus" -ForegroundColor $hostColor
Write-Host "Stability Score: $stabilityScore/10" -ForegroundColor Gray
Write-Host ""

# Save text report
"USB TREE REPORT - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $totalDevices`nTotal hubs: $totalHubs`n`nSTABILITY SUMMARY`n$statusSummaryTerminal`nHOST STATUS: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt
Write-Host "Report saved as: $outTxt" -ForegroundColor Gray

# Generate HTML report
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - $dateStamp</title>
    <style>
        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', 'Courier New', monospace; padding: 20px; font-size: 14px; }
        pre { margin: 0; white-space: pre; }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .gray { color: #c0c0c0; }
    </style>
</head>
<body>
<pre>
<span class="cyan">==============================================================================</span>
<span class="cyan">USB TREE REPORT - $dateStamp</span>
<span class="cyan">==============================================================================</span>

$treeOutput

<span class="gray">Furthest jumps: $maxHops</span>
<span class="gray">Number of tiers: $numTiers</span>
<span class="gray">Total devices: $totalDevices</span>
<span class="gray">Total hubs: $totalHubs</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $maxHops hops)</span>
<span class="cyan">==============================================================================</span>
$(foreach ($line in $statusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class='gray'>Host status:     </span><span class='$($hostColor.ToLower())'>$hostStatus</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$stabilityScore/10</span>
</pre>
</body>
</html>
"@
$htmlContent | Out-File $outHtml -Encoding UTF8
Write-Host "HTML report saved as: $outHtml" -ForegroundColor Gray

# Prompt to open HTML
$openHtml = Read-Host "Open HTML report? (y/n)"
if ($openHtml -eq 'y') { Start-Process $outHtml }

# ─────────────────────────────────────────────────────────────────────────────
# Prompt for deep analytics AFTER tree + HTML
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
$wantDeep = Read-Host "Run deep analytics / stability monitoring? (y/n)"
if ($wantDeep -notmatch '^[Yy]') {
    Write-Host "Deep analytics skipped." -ForegroundColor Gray
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# Run deep mode based on admin status
# ─────────────────────────────────────────────────────────────────────────────
$deepLog = "$env:TEMP\usb-deep-log-$dateStamp.txt"
$deepHtml = "$env:TEMP\usb-deep-report-$dateStamp.html"

if (-not $isAdmin) {
    # =========================================================================
    # BASIC DEEP ANALYTICS (Polling mode - re-handshakes only)
    # =========================================================================
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "STARTING BASIC DEEP ANALYTICS (re-handshakes / disconnects only)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "Mode: Polling (no admin required)" -ForegroundColor Yellow
    Write-Host "Log: $deepLog" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
    
    $script:StartTime = Get-Date
    $script:IsStable = $true
    $script:Rehandshakes = 0
    
    # Initial device snapshot
    $initialDevices = @{}
    foreach ($dev in (Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' })) {
        $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
        $initialDevices[$dev.InstanceId] = $name
    }
    
    function Write-Event {
        param($Type, $Message, $Device)
        $time = Get-Date -Format "HH:mm:ss.fff"
        $logLine = "[$time] [$Type] $Message $Device"
        Add-Content -Path $deepLog -Value $logLine
    }
    
    Write-Event -Type "INFO" -Message "Basic Deep Analytics started" -Device ""
    
    # Monitoring loop
    try {
        $previousDevices = $initialDevices.Clone()
        
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            
            $current = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
            $currentMap = @{}
            foreach ($dev in $current) { 
                $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
                $currentMap[$dev.InstanceId] = $name
            }
            
            # Check for disconnections (re-handshakes)
            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-Event -Type "REHANDSHAKE" -Message "Device disconnected" -Device $previousDevices[$id]
                    $script:Rehandshakes++
                    $script:IsStable = $false
                }
            }
            
            # Check for new connections
            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-Event -Type "CONNECT" -Message "Device connected" -Device $currentMap[$id]
                }
            }
            
            $previousDevices = $currentMap.Clone()
            
            # Clear and update display
            Clear-Host
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "==============================================================================" -ForegroundColor Cyan
            Write-Host "BASIC DEEP ANALYTICS - $([string]::Format('{0:hh\:mm\:ss}', $elapsed)) elapsed" -ForegroundColor Cyan
            Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host "==============================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "MODE: Basic (Polling)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "RE-HANDSHAKES: " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor Cyan
            
            $events = Get-Content $deepLog | Select-Object -Last 10
            if ($events.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor Gray
            } else {
                foreach ($event in $events) {
                    if ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor Yellow
                    } else {
                        Write-Host "  $event" -ForegroundColor Gray
                    }
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        # Generate summary and reports
        $elapsedTotal = (Get-Date) - $script:StartTime
        
        Clear-Host
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "BASIC DEEP ANALYTICS COMPLETE" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor Gray
        Write-Host "Final status: " -NoNewline
        Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
        Write-Host "Re-handshakes: $script:Rehandshakes" -ForegroundColor Gray
        Write-Host ""
        
        # Generate HTML report for basic deep analytics
        $eventHtml = ""
        foreach ($event in (Get-Content $deepLog)) {
            if ($event -match "REHANDSHAKE") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } else {
                $eventHtml += "  <span class='gray'>$event</span>`r`n"
            }
        }
        
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Basic Deep Analytics Report</title>
    <style>
        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', 'Courier New', monospace; padding: 20px; font-size: 14px; }
        pre { margin: 0; font-family: 'Consolas', 'Courier New', monospace; white-space: pre; }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .gray { color: #c0c0c0; }
    </style>
</head>
<body>
<pre>
<span class="cyan">==============================================================================</span>
<span class="cyan">USB BASIC DEEP ANALYTICS REPORT</span>
<span class="cyan">==============================================================================</span>

<span class="cyan">SUMMARY</span>
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Mode:            Basic (Polling)
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">==============================================================================</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "Log file: $deepLog" -ForegroundColor Gray
        Write-Host "HTML report: $deepHtml" -ForegroundColor Gray
        Write-Host ""
        
        $openDeep = Read-Host "Open Deep Analytics HTML report? (y/n)"
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }

} else {
    # =========================================================================
    # DEEPER ANALYTICS (ETW mode - CRC, resets, overcurrent, etc.)
    # =========================================================================
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "STARTING DEEPER ANALYTICS (CRC, resets, overcurrent, re-handshakes + more)" -ForegroundColor Magenta
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "Mode: ETW Tracing (admin required)" -ForegroundColor Green
    Write-Host "Log: $deepLog" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
    
    $script:StartTime = Get-Date
    $script:IsStable = $true
    $script:CRCFailures = 0
    $script:BusResets = 0
    $script:Overcurrent = 0
    $script:Rehandshakes = 0
    $script:OtherErrors = 0
    
    # Start ETW trace for USB
    $traceName = "LK_USB_TRACE_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    
    try {
        # Start USB trace (Microsoft-Windows-USB-UCX or similar providers)
        logman create trace $traceName -p "Microsoft-Windows-USB-UCX" -o "$env:TEMP\usb-etw.etl" -ets
        logman start $traceName -ets
        
        Write-EventLog -Type "INFO" -Message "ETW trace started" -Device ""
        
        function Write-EventLog {
            param($Type, $Message, $Device)
            $time = Get-Date -Format "HH:mm:ss.fff"
            $logLine = "[$time] [$Type] $Message $Device"
            Add-Content -Path $deepLog -Value $logLine
        }
        
        # Monitor loop with Get-WinEvent
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            
            # Query ETW events
            $events = Get-WinEvent -ListLog "Microsoft-Windows-USB-UCX/Operational" -ErrorAction SilentlyContinue
            if ($events) {
                $recentEvents = Get-WinEvent -LogName "Microsoft-Windows-USB-UCX/Operational" -MaxEvents 50 -ErrorAction SilentlyContinue
                
                foreach ($event in $recentEvents) {
                    $eventMessage = $event.Message
                    $eventTime = $event.TimeCreated.ToString("HH:mm:ss.fff")
                    
                    # Pattern matching for various USB errors
                    if ($eventMessage -match "CRC|checksum|corrupt") {
                        Write-EventLog -Type "CRC_ERROR" -Message "CRC failure detected" -Device ""
                        $script:CRCFailures++
                        $script:IsStable = $false
                    }
                    elseif ($eventMessage -match "reset|bus reset|port reset") {
                        Write-EventLog -Type "BUS_RESET" -Message "Bus reset occurred" -Device ""
                        $script:BusResets++
                        $script:IsStable = $false
                    }
                    elseif ($eventMessage -match "overcurrent|over current|power surge") {
                        Write-EventLog -Type "OVERCURRENT" -Message "Overcurrent condition" -Device ""
                        $script:Overcurrent++
                        $script:IsStable = $false
                    }
                    elseif ($eventMessage -match "disconnect|reconnect|re-handshake|handshake") {
                        Write-EventLog -Type "REHANDSHAKE" -Message "Device re-handshake" -Device ""
                        $script:Rehandshakes++
                        $script:IsStable = $false
                    }
                    elseif ($eventMessage -match "error|failed|timeout") {
                        Write-EventLog -Type "OTHER_ERROR" -Message "Other error: $eventMessage" -Device ""
                        $script:OtherErrors++
                        $script:IsStable = $false
                    }
                }
            }
            
            # Also monitor device presence changes (like basic mode)
            $currentDevices = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
            # ... (add device change detection if needed)
            
            # Clear and update display
            Clear-Host
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "DEEPER ANALYTICS - $([string]::Format('{0:hh\:mm\:ss}', $elapsed)) elapsed" -ForegroundColor Magenta
            Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "MODE: ETW Tracing (Advanced)" -ForegroundColor Green
            Write-Host ""
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "CRC FAILURES:   " -NoNewline
            Write-Host "$($script:CRCFailures.ToString('D2'))" -ForegroundColor $(if ($script:CRCFailures -gt 0) { "Magenta" } else { "Gray" })
            Write-Host "BUS RESETS:     " -NoNewline
            Write-Host "$($script:BusResets.ToString('D2'))" -ForegroundColor $(if ($script:BusResets -gt 0) { "Yellow" } else { "Gray" })
            Write-Host "OVERCURRENT:    " -NoNewline
            Write-Host "$($script:Overcurrent.ToString('D2'))" -ForegroundColor $(if ($script:Overcurrent -gt 0) { "Magenta" } else { "Gray" })
            Write-Host "RE-HANDSHAKES:  " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
            Write-Host "OTHER ERRORS:   " -NoNewline
            Write-Host "$($script:OtherErrors.ToString('D2'))" -ForegroundColor $(if ($script:OtherErrors -gt 0) { "Yellow" } else { "Gray" })
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor Cyan
            
            $events = Get-Content $deepLog | Select-Object -Last 15
            if ($events.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor Gray
            } else {
                foreach ($event in $events) {
                    if ($event -match "CRC_ERROR") {
                        Write-Host "  $event" -ForegroundColor Magenta
                    } elseif ($event -match "OVERCURRENT") {
                        Write-Host "  $event" -ForegroundColor Magenta
                    } elseif ($event -match "BUS_RESET") {
                        Write-Host "  $event" -ForegroundColor Yellow
                    } elseif ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor Yellow
                    } elseif ($event -match "OTHER_ERROR") {
                        Write-Host "  $event" -ForegroundColor Yellow
                    } else {
                        Write-Host "  $event" -ForegroundColor Gray
                    }
                }
            }
            
            Start-Sleep -Seconds 2
        }
    }
    finally {
        # Stop and clean up ETW trace
        logman stop $traceName -ets
        logman delete $traceName
        
        $elapsedTotal = (Get-Date) - $script:StartTime
        
        Clear-Host
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "DEEPER ANALYTICS COMPLETE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor Gray
        Write-Host "Final status: " -NoNewline
        Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
        Write-Host ""
        Write-Host "CRC Failures:   $script:CRCFailures" -ForegroundColor $(if ($script:CRCFailures -gt 0) { "Magenta" } else { "Gray" })
        Write-Host "Bus Resets:     $script:BusResets" -ForegroundColor $(if ($script:BusResets -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "Overcurrent:    $script:Overcurrent" -ForegroundColor $(if ($script:Overcurrent -gt 0) { "Magenta" } else { "Gray" })
        Write-Host "Re-handshakes:  $script:Rehandshakes" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "Other Errors:   $script:OtherErrors" -ForegroundColor $(if ($script:OtherErrors -gt 0) { "Yellow" } else { "Gray" })
        Write-Host ""
        
        # Generate HTML report for deeper analytics
        $eventHtml = ""
        foreach ($event in (Get-Content $deepLog)) {
            if ($event -match "CRC_ERROR") {
                $eventHtml += "  <span class='magenta'>$event</span>`r`n"
            } elseif ($event -match "OVERCURRENT") {
                $eventHtml += "  <span class='magenta'>$event</span>`r`n"
            } elseif ($event -match "BUS_RESET") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } elseif ($event -match "REHANDSHAKE") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } elseif ($event -match "OTHER_ERROR") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } else {
                $eventHtml += "  <span class='gray'>$event</span>`r`n"
            }
        }
        
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Deeper Analytics Report</title>
    <style>
        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', 'Courier New', monospace; padding: 20px; font-size: 14px; }
        pre { margin: 0; font-family: 'Consolas', 'Courier New', monospace; white-space: pre; }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .gray { color: #c0c0c0; }
    </style>
</head>
<body>
<pre>
<span class="cyan">==============================================================================</span>
<span class="cyan">USB DEEPER ANALYTICS REPORT</span>
<span class="cyan">==============================================================================</span>

<span class="cyan">SUMMARY</span>
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Mode:            ETW Tracing (Advanced)
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>

  CRC Failures:    <span class="$(if ($script:CRCFailures -gt 0) { 'magenta' } else { 'gray' })">$script:CRCFailures</span>
  Bus Resets:      <span class="$(if ($script:BusResets -gt 0) { 'yellow' } else { 'gray' })">$script:BusResets</span>
  Overcurrent:     <span class="$(if ($script:Overcurrent -gt 0) { 'magenta' } else { 'gray' })">$script:Overcurrent</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  Other Errors:    <span class="$(if ($script:OtherErrors -gt 0) { 'yellow' } else { 'gray' })">$script:OtherErrors</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">==============================================================================</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "Log file: $deepLog" -ForegroundColor Gray
        Write-Host "HTML report: $deepHtml" -ForegroundColor Gray
        Write-Host ""
        
        $openDeep = Read-Host "Open Deeper Analytics HTML report? (y/n)"
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
