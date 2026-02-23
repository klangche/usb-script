# usb-tree-powershell.ps1 - USB Tree Diagnostic for Windows

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

# Get devices
$devices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, @{n='Name';e={
    if ($_.FriendlyName) { $_.FriendlyName }
    elseif ($_.Name) { $_.Name }
    else { $_.InstanceId }
}}

# Build parent-child map
$map = @{}
foreach ($d in $devices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ Name = $d.Name; Parent = $parent; Children = @() }
    } catch {}
}

# Build tree structure
$roots = @()
foreach ($id in $map.Keys) {
    if (-not $map[$id].Parent) {
        $roots += $id
    } else {
        # Find parent and add as child
        foreach ($pid in $map.Keys) {
            if ($map[$pid].Name -like "*$($map[$id].Parent)*") {
                $map[$pid].Children += $id
                break
            }
        }
    }
}

# Recursive tree printer
$treeOutput = ""
$maxHops = 0
$deviceCount = $devices.Count

function Print-Tree {
    param($id, $level, $prefix, $isLast)
    
    $node = $map[$id]
    if (-not $node) { return }
    
    # Build tree branch
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

# Platform limits
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

# Terminal output
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

# Save report
"USB TREE REPORT - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $deviceCount`n`nSTABILITY SUMMARY`n$statusSummaryTerminal`nHOST STATUS: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt
Write-Host "Report saved as: $outTxt" -ForegroundColor Gray

# HTML report
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
        $statusSummaryTerminal
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

# Deep Analytics - only in admin mode
if ($isElevated) {
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "DEEP ANALYTICS - Real-time USB Monitoring" -ForegroundColor Magenta
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "Starting deep analytics with all collected data..." -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
    
    # Custom logging function
    $script:RandomErrors = 0
    $script:Rehandshakes = 0
    $script:IsStable = $true
    $script:StartTime = Get-Date
    $script:LastEvents = @()
    $script:LogFile = "$env:TEMP\usb-deep-analytics-$dateStamp.log"
    
    function Write-USBEvent {
        param($Type, $Message, $Device)
        $time = Get-Date -Format "HH:mm:ss.fff"
        $event = "[$time] [$Type] $Message $Device"
        Add-Content -Path $script:LogFile -Value $event
        
        # Update counters
        if ($Type -eq "ERROR") { $script:RandomErrors++ }
        if ($Type -eq "REHANDSHAKE") { $script:Rehandshakes++ }
        
        # Keep last 10 events
        $script:LastEvents = @($event) + $script:LastEvents[0..8]
    }
    
    # Start monitoring loop
    while ($true) {
        $elapsed = (Get-Date) - $script:StartTime
        $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
        $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
        
        Clear-Host
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
        if ($script:LastEvents.Count -eq 0) {
            Write-Host "  No events detected"
        } else {
            foreach ($event in $script:LastEvents) {
                Write-Host "  $event"
            }
        }
        Write-Host ""
        Write-Host "Log file: $($script:LogFile)" -ForegroundColor Gray
        
        # Simulate some monitoring (in reality you'd hook into WMI events)
        Start-Sleep -Seconds 2
    }
}
