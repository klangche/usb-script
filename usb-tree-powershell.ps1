# =============================================================================
# USB Tree Diagnostic Tool - Windows PowerShell Edition
# =============================================================================
# Enumerates USB devices, builds a tree view, assesses stability by hops, and
# optionally runs deep analytics for monitoring. Generates text/HTML reports.
#
# Features:
# - Admin handling with relaunch if needed.
# - Hierarchy mapping using registry for parents/children.
# - Platform stability ratings.
# - Optional real-time monitoring (deep analytics).
#
# TODO: Test on Windows 11 ARM for Silicon-specific tweaks.
# TODO: Add voltage/power querying via WMI if possible.
#
# DEBUG TIP: If map empty, dump $allDevices to file: $allDevices | Export-Csv temp.csv
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# Smart admin handling.
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

# Enumeration.
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

Write-Host "Enumerating USB devices..." -ForegroundColor Gray

$allDevices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, FriendlyName, Name, Class, @{n='IsHub';e={
    ($_.FriendlyName -like "*hub*") -or ($_.Name -like "*hub*") -or ($_.Class -eq "USBHub") -or ($_.InstanceId -like "*HUB*")
}}

# Error check.
if ($allDevices.Count -eq 0) {
    Write-Host "No USB devices found." -ForegroundColor Yellow
    # DEBUG TIP: Check WMI status.
    Get-WmiObject Win32_USBHub | Out-File /tmp/usb-wmi.txt
    exit
}

$devices = $allDevices | Where-Object { -not $_.IsHub }
$hubs = $allDevices | Where-Object { $_.IsHub }

Write-Host "Found $($devices.Count) devices and $($hubs.Count) hubs" -ForegroundColor Gray

# Build map.
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

# Hierarchy.
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

# Tree generation.
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

# Stability.
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

# Host status (for Windows).
$hostStatus = ($statusLines | Where-Object { $_.Platform -eq "Windows" }).Status
$hostColor = if ($hostStatus -eq "STABLE") { "Green" } elseif ($hostStatus -eq "POTENTIALLY UNSTABLE") { "Yellow" } else { "Magenta" }

# Terminal output.
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

# Save text report.
"USB TREE REPORT - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $totalDevices`nTotal hubs: $totalHubs`n`nSTABILITY SUMMARY`n$statusSummaryTerminal`nHOST STATUS: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt
Write-Host "Report saved as: $outTxt" -ForegroundColor Gray

# HTML report generation (reconstructed from truncated content, tidied).
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
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>"
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

$openHtml = Read-Host "Open HTML report? (y/n)"
if ($openHtml -eq 'y') { Start-Process $outHtml }

# Deep analytics (from truncated content, tidied with error checks).
$deepChoice = Read-Host "Run Deep Analytics (monitor for stability over time)? (y/n)"
if ($deepChoice -eq 'y') {
    $deepLog = "$env:TEMP\usb-deep-log-$dateStamp.txt"
    $deepHtml = "$env:TEMP\usb-deep-report-$dateStamp.html"
    
    $script:StartTime = Get-Date
    $script:IsStable = $true
    $script:RandomErrors = 0
    $script:Rehandshakes = 0
    
    # Initial devices.
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
    
    Write-Event -Type "INFO" -Message "Deep Analytics started" -Device ""
    
    # Monitoring loop.
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
            
            # Disconnections.
            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-Event -Type "REHANDSHAKE" -Message "Device disconnected" -Device $previousDevices[$id]
                    $script:Rehandshakes++
                    $script:IsStable = $false
                }
            }
            
            # New connections.
            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-Event -Type "INFO" -Message "Device connected" -Device $currentMap[$id]
                }
            }
            
            $previousDevices = $currentMap.Clone()
            
            # Display (clear for clean view).
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
        
        # Deep HTML (tidied).
        $daPlatformHtml = ""
        foreach ($line in $statusLines) {
            $color = if ($line.Status -eq "STABLE") { "green" } 
                     elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } 
                     else { "magenta" }
            $daPlatformHtml += "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$color'>$($line.Status)</span>`r`n"
        }
        
        $eventHtml = ""
        foreach ($event in (Get-Content $deepLog)) {
            if ($event -match "ERROR") {
                $eventHtml += "  <span class='magenta'>$event</span>`r`n"
            } elseif ($event -match "REHANDSHAKE") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } else {
                $eventHtml += "  <span class='gray'>$event</span>`r`n"
            }
        }
        
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
$daPlatformHtml
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
        
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
} else {
    Write-Host "Deep Analytics skipped." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
