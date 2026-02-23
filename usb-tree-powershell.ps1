# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# This script enumerates USB devices and displays them in a tree structure
# It assesses stability based on USB hops and platform limits
#
# FEATURES:
# - Smart admin detection (doesn't ask twice)
# - Tree view with proper hierarchy
# - Stability assessment per platform
# - HTML report (exact terminal look - black background)
# - Optional Deep Analytics (clean terminal view)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# SMART ADMIN HANDLING - Only asks once
# =============================================================================
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    $adminChoice = Read-Host "Run with admin for maximum detail? (y/n)"
    
    if ($adminChoice -eq 'y') {
        Write-Host "Requesting administrator privileges..." -ForegroundColor Yellow
        
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = "$env:TEMP\usb-tree-temp.ps1"
            $scriptContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
            $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8
        }
        
        $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process powershell -ArgumentList $psArgs -Verb RunAs
        Write-Host "Admin process launched. This window will close..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        exit
    } else {
        Write-Host "Running without admin privileges (basic mode)." -ForegroundColor Yellow
    }
} else {
    Write-Host "✓ Running with administrator privileges." -ForegroundColor Green
}
Write-Host ""

# =============================================================================
# USB DEVICE ENUMERATION
# =============================================================================
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

Write-Host "Enumerating USB devices..." -ForegroundColor Gray

# Get all USB devices
$allDevices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, FriendlyName, Name, Class, @{n='IsHub';e={
    ($_.FriendlyName -like "*hub*") -or ($_.Name -like "*hub*") -or ($_.Class -eq "USBHub") -or ($_.InstanceId -like "*HUB*")
}}

# Separate devices and hubs
$devices = $allDevices | Where-Object { -not $_.IsHub }
$hubs = $allDevices | Where-Object { $_.IsHub }

Write-Host "Found $($devices.Count) devices and $($hubs.Count) hubs" -ForegroundColor Gray

# Build parent-child relationship map for ALL devices (including hubs for tree structure)
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

# Build tree hierarchy
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

# =============================================================================
# TREE VIEW GENERATION
# =============================================================================
$treeOutput = ""
$maxHops = 0

function Print-Tree {
    param($id, $level, $prefix, $isLast)
    
    $node = $map[$id]
    if (-not $node) { return }
    
    $branch = if ($level -eq 0) { "└── " } else { $prefix + $(if ($isLast) { "└── " } else { "├── " }) }
    
    # Mark hubs with [HUB] for clarity
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

# Host status
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

# =============================================================================
# SAVE TEXT REPORT
# =============================================================================
"USB TREE REPORT - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $totalDevices`nTotal hubs: $totalHubs`n`nSTABILITY SUMMARY`n$statusSummaryTerminal`nHOST STATUS: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt
Write-Host "Report saved as: $outTxt" -ForegroundColor Gray

# =============================================================================
# HTML REPORT - EXAKT SOM TERMINAL (svart bakgrund, white-space: pre)
# =============================================================================
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report</title>
    <style>
        body { 
            background: #000000; 
            color: #e0e0e0; 
            font-family: 'Consolas', 'Courier New', monospace; 
            padding: 20px;
            font-size: 14px;
        }
        pre { 
            margin: 0; 
            font-family: 'Consolas', 'Courier New', monospace;
            color: #e0e0e0;
            white-space: pre;
        }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .white { color: #ffffff; }
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
    $color = if ($line.Status -eq "STABLE") { "green" } 
             elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } 
             else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$color'>$($line.Status)</span>"
})
<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class='gray'>Host status:     </span><span class="$($hostColor.ToLower())">$hostStatus</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$stabilityScore/10</span>
</pre>
</body>
</html>
"@
$html | Out-File $outHtml

$open = Read-Host "Open HTML report in browser? (y/n)"
if ($open -eq 'y') { Start-Process $outHtml }

# =============================================================================
# DEEP ANALYTICS - Clean terminal view
# =============================================================================
if ($isElevated) {
    Write-Host ""
    $runDeep = Read-Host "Run Deep Analytics to monitor USB stability? (y/n)"
    
    if ($runDeep -eq 'y') {
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "DEEP ANALYTICS - USB Event Monitoring" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "Monitoring USB connections... Press Ctrl+C to stop" -ForegroundColor Gray
        Write-Host ""
        
        # Simple counters
        $script:RandomErrors = 0
        $script:Rehandshakes = 0
        $script:IsStable = $true
        $script:StartTime = Get-Date
        $deepLog = "$env:TEMP\usb-deep-analytics-$dateStamp.log"
        $deepHtml = "$env:TEMP\usb-deep-analytics-$dateStamp.html"
        
        # Store initial connected devices
        $initialDevices = @{}
        foreach ($d in $allDevices) {
            $initialDevices[$d.InstanceId] = if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }
        }
        
        # Simple logging function
        function Write-Event {
            param($Type, $Message, $Device)
            $time = Get-Date -Format "HH:mm:ss.fff"
            $logLine = "[$time] [$Type] $Message $Device"
            Add-Content -Path $deepLog -Value $logLine
        }
        
        Write-Event -Type "INFO" -Message "Deep Analytics started" -Device ""
        
        # Simple monitoring loop
        try {
            $previousDevices = $initialDevices.Clone()
            
            while ($true) {
                $elapsed = (Get-Date) - $script:StartTime
                
                # Get current devices
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
                        Write-Event -Type "INFO" -Message "Device connected" -Device $currentMap[$id]
                    }
                }
                
                $previousDevices = $currentMap.Clone()
                
                # Clear and update display (clean view)
                Clear-Host
                $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
                $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
                
                Write-Host "==============================================================================" -ForegroundColor Magenta
                Write-Host "DEEP ANALYTICS - $([string]::Format('{0:hh\:mm\:ss}', $elapsed)) elapsed" -ForegroundColor Magenta
                Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
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
                
                # Show last 10 events
                $events = Get-Content $deepLog | Where-Object { $_ -notmatch "Device detected" } | Select-Object -Last 10
                if ($events.Count -eq 0) {
                    Write-Host "  No events detected" -ForegroundColor Gray
                } else {
                    foreach ($event in $events) {
                        if ($event -match "ERROR") {
                            Write-Host "  $event" -ForegroundColor Magenta
                            $script:RandomErrors++
                            $script:IsStable = $false
                        } elseif ($event -match "REHANDSHAKE") {
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
            $elapsedTotal = (Get-Date) - $script:StartTime
            
            Write-Host ""
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "DEEP ANALYTICS COMPLETE" -ForegroundColor Magenta
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor Gray
            Write-Host "Final status: " -NoNewline
            Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
            Write-Host "Random errors: $script:RandomErrors" -ForegroundColor Gray
            Write-Host "Re-handshakes: $script:Rehandshakes" -ForegroundColor Gray
            Write-Host ""
            
            # HTML REPORT for Deep Analytics - EXAKT SOM TERMINAL (svart bakgrund, white-space: pre)
            $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Deep Analytics Report</title>
    <style>
        body { 
            background: #000000; 
            color: #e0e0e0; 
            font-family: 'Consolas', 'Courier New', monospace; 
            padding: 20px;
            font-size: 14px;
        }
        pre { 
            margin: 0; 
            font-family: 'Consolas', 'Courier New', monospace;
            color: #e0e0e0;
            white-space: pre;
        }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .white { color: #ffffff; }
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
    $color = if ($line.Status -eq "STABLE") { "green" } 
             elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } 
             else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$color'>$($line.Status)</span>"
})
<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class='gray'>Host status:     </span><span class="$($hostColor.ToLower())">$hostStatus</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$stabilityScore/10</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">DEEP ANALYTICS - $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal)) elapsed</span>
<span class="cyan">==============================================================================</span>

  <span class='gray'>Final status:     </span><span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  <span class='gray'>Random errors:    </span><span class="$(if ($script:RandomErrors -gt 0) { 'yellow' } else { 'gray' })">$script:RandomErrors</span>
  <span class='gray'>Re-handshakes:    </span><span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">EVENT LOG (in chronological order)</span>
<span class="cyan">==============================================================================</span>
$(foreach ($event in (Get-Content $deepLog)) {
    if ($event -match "ERROR") {
        "  <span class='magenta'>$event</span>"
    } elseif ($event -match "REHANDSHAKE") {
        "  <span class='yellow'>$event</span>"
    } else {
        "  <span class='gray'>$event</span>"
    }
})
</pre>
</body>
</html>
"@
            $deepHtmlContent | Out-File -FilePath $deepHtml -Encoding UTF8
            
            Write-Host "Log file: $deepLog" -ForegroundColor Gray
            Write-Host "HTML report: $deepHtml" -ForegroundColor Gray
            Write-Host ""
            
            $openDeep = Read-Host "Open Deep Analytics HTML report? (y/n)"
            if ($openDeep -eq 'y') { Start-Process $deepHtml }
        }
    } else {
        Write-Host "Deep Analytics skipped." -ForegroundColor Gray
    }
}
