# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# This script enumerates USB devices and displays them in a tree structure
# It assesses stability based on USB hops and platform limits
#
# FEATURES:
# - Admin mode for maximum detail
# - Tree view with proper hierarchy
# - Stability assessment per platform
# - HTML report generation
# - Deep Analytics (auto-starts after admin mode)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# Ask for admin mode
$adminChoice = Read-Host "Run with admin for maximum detail? (y/n)"
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($adminChoice -eq 'y' -and -not $isElevated) {
    Write-Host "Relaunching as administrator..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Running with admin: $isElevated" -ForegroundColor $(if ($isElevated) { "Green" } else { "Yellow" })
Write-Host ""

$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

# =============================================================================
# USB DEVICE ENUMERATION
# =============================================================================
Write-Host "Enumerating USB devices..." -ForegroundColor Gray

$devices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, @{n='Name';e={
    if ($_.FriendlyName) { $_.FriendlyName }
    elseif ($_.Name) { $_.Name }
    else { $_.InstanceId }
}}

# Build parent-child relationship map
$map = @{}
foreach ($d in $devices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ 
            Name = $d.Name
            Parent = $parent
            Children = @()
            InstanceId = $d.InstanceId
        }
    } catch {
        # Fallback - add without parent info
        $map[$d.InstanceId] = @{ 
            Name = $d.Name
            Parent = $null
            Children = @()
            InstanceId = $d.InstanceId
        }
    }
}

# Build tree hierarchy
$roots = @()
foreach ($id in $map.Keys) {
    $node = $map[$id]
    if (-not $node.Parent) {
        $roots += $id
    } else {
        # Find parent and add as child
        foreach ($pid in $map.Keys) {
            if ($map[$pid].Name -like "*$($node.Parent)*" -or $map[$pid].InstanceId -like "*$($node.Parent)*") {
                $map[$pid].Children += $id
                break
            }
        }
    }
}

# =============================================================================
# TREE VIEW GENERATION
# =============================================================================
$treeOutput = ""
$maxHops = 0
$deviceCount = $devices.Count

function Print-Tree {
    param($id, $level, $prefix, $isLast)
    
    $node = $map[$id]
    if (-not $node) { return }
    
    # Build tree branch with proper characters
    $branch = ""
    if ($level -eq 0) {
        $branch = "└── "
    } else {
        $branch = $prefix + $(if ($isLast) { "└── " } else { "├── " })
    }
    
    $script:treeOutput += "$branch$($node.Name) ← $level hops`n"
    $script:maxHops = [Math]::Max($script:maxHops, $level)
    
    # New prefix for children
    $newPrefix = $prefix + $(if ($isLast) { "    " } else { "│   " })
    
    $children = $node.Children
    for ($i = 0; $i -lt $children.Count; $i++) {
        $isLastChild = ($i -eq $children.Count - 1)
        Print-Tree -id $children[$i] -level ($level + 1) -prefix $newPrefix -isLast $isLastChild
    }
}

# Print all roots
foreach ($root in $roots) {
    Print-Tree -id $root -level 0 -prefix "" -isLast $true
}

$numTiers = $maxHops + 1
$stabilityScore = [Math]::Max(1, 9 - $maxHops)

# =============================================================================
# STABILITY ASSESSMENT
# =============================================================================
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

# Build status lines
$statusLines = @()
foreach ($plat in $platforms.Keys) {
    $rec = $platforms[$plat].rec
    $max = $platforms[$plat].max
    $status = if ($numTiers -le $rec) { "STABLE" } 
              elseif ($numTiers -le $max) { "POTENTIALLY UNSTABLE" } 
              else { "NOT STABLE" }
    $statusLines += [PSCustomObject]@{ Platform = $plat; Status = $status }
}

# Sort in consistent order
$order = @("Windows", "Linux", "Mac Intel", "Mac Apple Silicon", "iPad USB-C (M-series)", "iPhone USB-C", "Android Phone (Qualcomm)", "Android Tablet (Exynos)")
$statusLines = $statusLines | Sort-Object { $order.IndexOf($_.Platform) }

$maxPlatLen = ($statusLines.Platform | Measure-Object Length -Maximum).Maximum
$statusSummaryTerminal = ""
foreach ($line in $statusLines) {
    $pad = " " * ($maxPlatLen - $line.Platform.Length + 4)
    $statusSummaryTerminal += "$($line.Platform)$pad$($line.Status)`n"
}

# Host status (Mac Apple Silicon is the bottleneck)
$macAsStatus = ($statusLines | Where-Object { $_.Platform -eq "Mac Apple Silicon" }).Status

if ($macAsStatus -eq "NOT STABLE") {
    $hostStatus = "NOT STABLE"
    $hostColor = "Magenta"
} elseif ($macAsStatus -eq "POTENTIALLY UNSTABLE") {
    $hostStatus = "POTENTIALLY UNSTABLE"
    $hostColor = "Yellow"
} else {
    $hasNotStable = $false
    $hasPotentially = $false
    foreach ($line in $statusLines) {
        if ($line.Platform -eq "Mac Apple Silicon") { continue }
        if ($line.Status -eq "NOT STABLE") { $hasNotStable = $true }
        if ($line.Status -eq "POTENTIALLY UNSTABLE") { $hasPotentially = $true }
    }
    if ($hasNotStable) {
        $hostStatus = "NOT STABLE"
        $hostColor = "Magenta"
    } elseif ($hasPotentially) {
        $hostStatus = "POTENTIALLY UNSTABLE"
        $hostColor = "Yellow"
    } else {
        $hostStatus = "STABLE"
        $hostColor = "Green"
    }
}

# =============================================================================
# TERMINAL OUTPUT
# =============================================================================
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host $treeOutput
Write-Host ""
Write-Host "Furthest jumps: $maxHops"
Write-Host "Number of tiers: $numTiers"
Write-Host "Total devices: $deviceCount"
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
Write-Host "Stability Score: $stabilityScore/10"
Write-Host ""

# =============================================================================
# SAVE TEXT REPORT
# =============================================================================
"USB TREE REPORT - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $deviceCount`n`nSTABILITY SUMMARY`n$statusSummaryTerminal`nHOST STATUS: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt
Write-Host "Report saved as: $outTxt" -ForegroundColor Gray

# =============================================================================
# HTML REPORT
# =============================================================================
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Diagnostic Report</title>
    <style>
        body { font-family: 'Consolas', monospace; background: #0d1117; color: #e6edf3; padding: 30px; }
        h1 { color: #79c0ff; border-bottom: 2px solid #30363d; }
        h2 { color: #79c0ff; margin-top: 30px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; color: #7ee787; white-space: pre-wrap; }
        .stable { color: #7ee787; }
        .warning { color: #ffa657; }
        .critical { color: #ff7b72; }
        .summary { background: #161b22; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <h1>USB Tree Diagnostic Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(Get-Date)</p>
        <p><strong>Platform:</strong> Windows $([System.Environment]::OSVersion.VersionString)</p>
        <p><strong>Max hops:</strong> $maxHops</p>
        <p><strong>External hubs:</strong> $($maxHops - 1)</p>
        <p><strong>Total tiers:</strong> $numTiers</p>
    </div>
    
    <h2>USB Device Tree</h2>
    <pre>$treeOutput</pre>
    
    <h2>Stability Assessment</h2>
    <div class="summary">
        <pre>$statusSummaryTerminal</pre>
    </div>
    
    <h2>Host Status</h2>
    <div class="summary">
        <p><strong>Status:</strong> <span style="color: $(if ($hostStatus -eq 'STABLE') { '#7ee787' } elseif ($hostStatus -eq 'POTENTIALLY UNSTABLE') { '#ffa657' } else { '#ff7b72' })">$hostStatus</span></p>
        <p><strong>Score:</strong> $stabilityScore/10</p>
    </div>
</body>
</html>
"@
$html | Out-File $outHtml

$open = Read-Host "Open HTML report in browser? (y/n)"
if ($open -eq 'y') { Start-Process $outHtml }

# =============================================================================
# DEEP ANALYTICS - High-Frequency USB Monitoring
# =============================================================================
if ($isElevated) {
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "DEEP ANALYTICS - High-Frequency USB Monitoring" -ForegroundColor Magenta
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "Monitoring USB stability with millisecond precision..." -ForegroundColor Gray
    Write-Host "Events are captured in real-time, display updates every 2 seconds" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop and generate HTML report" -ForegroundColor Yellow
    Write-Host ""
    
    # Initialize counters
    $script:RandomErrors = 0
    $script:Rehandshakes = 0
    $script:IsStable = $true
    $script:StartTime = Get-Date
    $script:LastEvents = @()
    $script:EventQueue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
    
    # Use same timestamp as main report
    $deepLog = "$env:TEMP\usb-deep-analytics-$dateStamp.log"
    $deepHtml = "$env:TEMP\usb-deep-analytics-$dateStamp.html"
    
    # High-precision event logging
    function Write-USBEvent {
        param(
            [string]$Type,
            [string]$Message,
            [string]$Device = ""
        )
        
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.ffffff"
        $display = "[$(Get-Date -Format 'HH:mm:ss.ffffff')] [$Type] $Message $Device"
        
        # Add to queue for display
        $script:EventQueue.Enqueue([PSCustomObject]@{
            Timestamp = $timestamp
            Display = $display
            Type = $Type
        })
        
        # Write to log file
        Add-Content -Path $deepLog -Value "$timestamp [$Type] $Message $Device"
        
        # Update counters
        if ($Type -eq "ERROR") { 
            $script:RandomErrors++
            $script:IsStable = $false
        }
        if ($Type -eq "REHANDSHAKE") { 
            $script:Rehandshakes++
            $script:IsStable = $false
        }
    }
    
    # Log initial devices
    foreach ($device in $devices) {
        Write-USBEvent -Type "INFO" -Message "Device detected" -Device $device.Name
    }
    
    # =========================================================================
    # HIGH-FREQUENCY MONITORING (10ms sampling)
    # =========================================================================
    $monitoringJob = Start-Job -Name "USBMonitor" -ScriptBlock {
        param($logFile)
        
        # Previous state
        $previousDevices = @{}
        $lastSample = Get-Date
        
        while ($true) {
            $now = Get-Date
            if (($now - $lastSample).TotalMilliseconds -ge 10) {
                $lastSample = $now
                
                try {
                    # Get current USB state
                    $current = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | 
                               Where-Object { $_.Status -eq 'OK' } |
                               Select-Object InstanceId, FriendlyName
                    
                    $currentMap = @{}
                    foreach ($dev in $current) {
                        $currentMap[$dev.InstanceId] = $dev.FriendlyName
                    }
                    
                    # Check for disconnections
                    foreach ($id in $previousDevices.Keys) {
                        if (-not $currentMap.ContainsKey($id)) {
                            $output = [PSCustomObject]@{
                                Type = "REHANDSHAKE"
                                Message = "Device disconnected"
                                Device = $previousDevices[$id]
                            }
                            $output | ConvertTo-Json -Compress
                        }
                    }
                    
                    # Check for new connections
                    foreach ($id in $currentMap.Keys) {
                        if (-not $previousDevices.ContainsKey($id)) {
                            $output = [PSCustomObject]@{
                                Type = "INFO"
                                Message = "Device connected"
                                Device = $currentMap[$id]
                            }
                            $output | ConvertTo-Json -Compress
                        }
                    }
                    
                    $previousDevices = $currentMap
                } catch {
                    # Silently continue on errors
                }
            }
            
            # Small sleep to prevent CPU overload
            Start-Sleep -Milliseconds 1
        }
    } -ArgumentList $deepLog
    
    # =========================================================================
    # MAIN DISPLAY LOOP (updates every 2 seconds)
    # =========================================================================
    try {
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            # Read events from monitoring job
            while ($monitoringJob.HasMoreData) {
                $event = Receive-Job -Job $monitoringJob 2>&1
                if ($event) {
                    try {
                        $data = $event | ConvertFrom-Json
                        Write-USBEvent -Type $data.Type -Message $data.Message -Device $data.Device
                    } catch {
                        # Ignore parsing errors
                    }
                }
            }
            
            # Update display
            Clear-Host
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "DEEP ANALYTICS - $([string]::Format('{0:hh\:mm\:ss\.fff}', $elapsed)) elapsed" -ForegroundColor Magenta
            Write-Host "Sampling: 10ms | Display: 2s | Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "RANDOM ERRORS: " -NoNewline
            Write-Host "$($script:RandomErrors.ToString('D2'))" -ForegroundColor $(if ($script:RandomErrors -gt 0) { "Yellow" } else { "Gray" })
            Write-Host "RE-HANDSHAKES: " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor Cyan
            
            # Get latest events from queue (keep last 10)
            $displayEvents = @()
            $tempQueue = @()
            while ($script:EventQueue.TryDequeue([ref]$null, [ref]$null)) {
                # Just counting
            }
            
            if (Test-Path $deepLog) {
                $displayEvents = Get-Content $deepLog -Tail 10
            }
            
            if ($displayEvents.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor Gray
            } else {
                foreach ($event in $displayEvents) {
                    if ($event -match "ERROR") {
                        Write-Host "  $event" -ForegroundColor Magenta
                    } elseif ($event -match "REHANDSHAKE|WARNING") {
                        Write-Host "  $event" -ForegroundColor Yellow
                    } else {
                        Write-Host "  $event" -ForegroundColor Gray
                    }
                }
            }
            Write-Host ""
            Write-Host "Complete log: $deepLog" -ForegroundColor Gray
            
            Start-Sleep -Seconds 2
        }
    }
    finally {
        # Clean up monitoring job
        Stop-Job -Job $monitoringJob -ErrorAction SilentlyContinue
        Remove-Job -Job $monitoringJob -ErrorAction SilentlyContinue
        
        # Generate final HTML report
        $elapsedTotal = (Get-Date) - $script:StartTime
        
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Deep Analytics Report - High Frequency</title>
    <style>
        body { font-family: 'Consolas', monospace; background: #0d1117; color: #e6edf3; padding: 30px; }
        h1 { color: #79c0ff; border-bottom: 2px solid #30363d; }
        h2 { color: #79c0ff; margin-top: 30px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; color: #7ee787; white-space: pre-wrap; }
        .summary { background: #161b22; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .stable { color: #7ee787; font-weight: bold; }
        .warning { color: #ffa657; font-weight: bold; }
        .critical { color: #ff7b72; font-weight: bold; }
        .counter { display: inline-block; margin-right: 30px; }
        .counter-label { color: #8b949e; font-size: 14px; }
        .counter-value { font-size: 24px; font-weight: bold; }
        .event-log { background: #161b22; padding: 15px; border-radius: 8px; max-height: 400px; overflow-y: auto; }
        .event-line { padding: 2px 0; border-bottom: 1px solid #21262d; }
        .event-time { color: #8b949e; margin-right: 15px; }
    </style>
</head>
<body>
    <h1>USB Deep Analytics Report - High Frequency</h1>
    
    <div class="summary">
        <p><span style="color: #79c0ff;">Generated:</span> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')</p>
        <p><span style="color: #79c0ff;">Duration:</span> $([string]::Format('{0:hh\:mm\:ss\.fff}', $elapsedTotal))</p>
        <p><span style="color: #79c0ff;">Sampling:</span> 10ms</p>
        <p><span style="color: #79c0ff;">Final status:</span> <span class="$(if ($script:IsStable) { 'stable' } else { 'critical' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span></p>
    </div>
    
    <div class="summary">
        <div class="counter">
            <div class="counter-label">RANDOM ERRORS</div>
            <div class="counter-value $(if ($script:RandomErrors -gt 0) { 'critical' } else { '' })">$script:RandomErrors</div>
        </div>
        <div class="counter">
            <div class="counter-label">RE-HANDSHAKES</div>
            <div class="counter-value $(if ($script:Rehandshakes -gt 0) { 'warning' } else { '' })">$script:Rehandshakes</div>
        </div>
    </div>
    
    <h2>Complete Event Log</h2>
    <div class="event-log">
        $(foreach ($line in (Get-Content $deepLog)) {
            $color = if ($line -match "ERROR") { "critical" } elseif ($line -match "REHANDSHAKE|WARNING") { "warning" } else { "" }
            "<div class='event-line'><span class='event-time'>$($line.Substring(0,23))</span><span class='$color'>$($line.Substring(24))</span></div>"
        })
    </div>
</body>
</html>
"@
        
        $deepHtmlContent | Out-File -FilePath $deepHtml -Encoding UTF8
        
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "DEEP ANALYTICS COMPLETE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "Total runtime: $([string]::Format('{0:hh\:mm\:ss\.fff}', $elapsedTotal))"
        Write-Host "Final status: " -NoNewline
        Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
        Write-Host "Total random errors: $script:RandomErrors"
        Write-Host "Total re-handshakes: $script:Rehandshakes"
        Write-Host ""
        Write-Host "Log file: $deepLog"
        Write-Host "HTML report: $deepHtml"
        
        $openDeep = Read-Host "Open Deep Analytics HTML report? (y/n)"
        if ($openDeep -eq 'y') {
            Start-Process $deepHtml
        }
    }
}
