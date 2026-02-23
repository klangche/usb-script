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
# - Basic HTML report (terminal style)
# - Simple Deep Analytics (real-time monitoring)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# ADMIN HANDLING
# =============================================================================
$adminChoice = Read-Host "Run with admin for maximum detail? (y/n)"
$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($adminChoice -eq 'y') {
    if (-not $isElevated) {
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
        Write-Host "✓ Already running as administrator." -ForegroundColor Green
    }
} else {
    Write-Host "Running without admin privileges (basic mode)." -ForegroundColor Yellow
}
Write-Host ""

# =============================================================================
# USB DEVICE ENUMERATION
# =============================================================================
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

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
    
    $branch = if ($level -eq 0) { "└── " } else { $prefix + $(if ($isLast) { "└── " } else { "├── " }) }
    $script:treeOutput += "$branch$($node.Name) ← $level hops`n"
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
# BASIC HTML REPORT (TERMINAL STYLE)
# =============================================================================
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report</title>
    <style>
        body { background: #000; color: #ccc; font-family: 'Consolas', monospace; padding: 20px; }
        pre { color: #0f0; margin: 0; }
        .stable { color: #0f0; }
        .warning { color: #ffa500; }
        .critical { color: #ff69b4; }
    </style>
</head>
<body>
<pre>
==============================================================================
USB TREE REPORT - $dateStamp
==============================================================================

$treeOutput

Furthest jumps: $maxHops
Number of tiers: $numTiers
Total devices: $deviceCount

==============================================================================
STABILITY PER PLATFORM (based on $maxHops hops)
==============================================================================
$statusSummaryTerminal
==============================================================================
HOST SUMMARY
==============================================================================
Host status: $hostStatus
Stability Score: $stabilityScore/10
</pre>
</body>
</html>
"@
$html | Out-File $outHtml

$open = Read-Host "Open HTML report in browser? (y/n)"
if ($open -eq 'y') { Start-Process $outHtml }

# =============================================================================
# DEEP ANALYTICS - Simple Version
# =============================================================================
if ($isElevated) {
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "DEEP ANALYTICS - USB Monitoring" -ForegroundColor Magenta
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
    
    # Simple logging
    function Write-Event {
        param($Type, $Message)
        $time = Get-Date -Format "HH:mm:ss.fff"
        $logLine = "[$time] [$Type] $Message"
        Add-Content -Path $deepLog -Value $logLine
        Write-Host "  $logLine" -ForegroundColor $(if ($Type -eq "ERROR") { "Magenta" } elseif ($Type -eq "REHANDSHAKE") { "Yellow" } else { "Gray" })
        
        if ($Type -eq "ERROR") { $script:RandomErrors++; $script:IsStable = $false }
        if ($Type -eq "REHANDSHAKE") { $script:Rehandshakes++; $script:IsStable = $false }
    }
    
    Write-Event -Type "INFO" -Message "Deep Analytics started"
    
    # Simple monitoring loop (check every second)
    try {
        $previousDevices = @{}
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            # Get current devices
            $current = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
            $currentMap = @{}
            foreach ($dev in $current) { $currentMap[$dev.InstanceId] = $dev.FriendlyName }
            
            # Check for changes
            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-Event -Type "REHANDSHAKE" -Message "Device disconnected: $($previousDevices[$id])"
                }
            }
            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-Event -Type "INFO" -Message "Device connected: $($currentMap[$id])"
                }
            }
            
            $previousDevices = $currentMap
            
            # Display status
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
            
            $events = Get-Content $deepLog -Tail 5
            foreach ($event in $events) {
                if ($event -match "ERROR") {
                    Write-Host "  $event" -ForegroundColor Magenta
                } elseif ($event -match "REHANDSHAKE") {
                    Write-Host "  $event" -ForegroundColor Yellow
                } else {
                    Write-Host "  $event" -ForegroundColor Gray
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        $elapsedTotal = (Get-Date) - $script:StartTime
        
        # BASIC HTML REPORT for Deep Analytics
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Deep Analytics Report</title>
    <style>
        body { background: #000; color: #ccc; font-family: 'Consolas', monospace; padding: 20px; }
        pre { color: #0f0; margin: 0; }
        .stable { color: #0f0; }
        .warning { color: #ffa500; }
        .critical { color: #ff69b4; }
    </style>
</head>
<body>
<pre>
==============================================================================
USB DEEP ANALYTICS REPORT - $dateStamp
==============================================================================

Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
Final status: $(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })

Random errors: $script:RandomErrors
Re-handshakes: $script:Rehandshakes

==============================================================================
COMPLETE EVENT LOG
==============================================================================
$(Get-Content $deepLog | ForEach-Object { $_ })
</pre>
</body>
</html>
"@
        $deepHtmlContent | Out-File -FilePath $deepHtml -Encoding UTF8
        
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "DEEP ANALYTICS COMPLETE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))"
        Write-Host "Final status: " -NoNewline
        Write-Host "$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })" -ForegroundColor $(if ($script:IsStable) { "Green" } else { "Magenta" })
        Write-Host "Random errors: $script:RandomErrors"
        Write-Host "Re-handshakes: $script:Rehandshakes"
        Write-Host ""
        Write-Host "Log file: $deepLog"
        Write-Host "HTML report: $deepHtml"
        
        $openDeep = Read-Host "Open Deep Analytics HTML report? (y/n)"
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }
}
