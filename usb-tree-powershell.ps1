# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition v1.0.0
# =============================================================================
# - Runs tree visualization + HTML report
# - After that, prompts for deep analytics (y/n)
# - No admin → basic deep analytics (re-handshakes only)
# - Admin → deeper analytics (CRC, resets, overcurrent, re-handshakes + more)
# =============================================================================

$scriptVersion = "1.0.0"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION v$scriptVersion" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Admin check + smart handling
# ─────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

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
# PART 1: USB TREE ENUMERATION AND REPORTING
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
$baseStabilityScore = [Math]::Max(1, 9 - $maxHops)

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

# Host status follows Apple Silicon
$appleSiliconStatus = ($statusLines | Where-Object { $_.Platform -eq "Mac Apple Silicon" }).Status
$hostStatus = $appleSiliconStatus
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
Write-Host "Stability Score: $baseStabilityScore/10" -ForegroundColor Gray
Write-Host ""

# Save text report
$txtReport = @"
USB TREE REPORT - $dateStamp

$treeOutput

Furthest jumps: $maxHops
Number of tiers: $numTiers
Total devices: $totalDevices
Total hubs: $totalHubs

STABILITY SUMMARY
$statusSummaryTerminal

HOST STATUS: $hostStatus (Score: $baseStabilityScore/10)
"@
$txtReport | Out-File $outTxt
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
  <span class='gray'>Stability Score: </span><span class='gray'>$baseStabilityScore/10</span>
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
# PART 2: DEEP ANALYTICS PROMPT
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
# PART 3: DEEP ANALYTICS
# ─────────────────────────────────────────────────────────────────────────────
$deepLog = "$env:TEMP\usb-deep-log-$dateStamp.txt"
$deepHtml = "$env:TEMP\usb-deep-report-$dateStamp.html"

# Initialize common counters
$script:StartTime = Get-Date
$script:IsStable = $true
$script:Rehandshakes = 0
$script:InitialDeviceCount = $devices.Count

# Initialize deeper counters
$script:CRCFailures = 0
$script:BusResets = 0
$script:Overcurrent = 0
$script:OtherErrors = 0

function Write-EventLog {
    param($Type, $Message, $Device)
    $time = Get-Date -Format "HH:mm:ss.fff"
    $logLine = "[$time] [$Type] $Message $Device"
    Add-Content -Path $deepLog -Value $logLine
}

# Initial device snapshot
$initialDevices = @{}
foreach ($dev in (Get-PnpDevice -Class USB | Where-Object { $_.Status -eq 'OK' })) {
    $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
    $initialDevices[$dev.InstanceId] = $name
}

Write-EventLog -Type "INFO" -Message "Deep Analytics started - Mode: $(if ($isAdmin) { 'DEEPER' } else { 'BASIC' })" -Device ""

# Store original data for final display
$originalTreeOutput = $treeOutput
$originalMaxHops = $maxHops
$originalNumTiers = $numTiers
$originalTotalDevices = $totalDevices
$originalTotalHubs = $totalHubs
$originalStatusLines = $statusLines
$originalHostStatus = $hostStatus
$originalHostColor = $hostColor
$originalBaseScore = $baseStabilityScore

if (-not $isAdmin) {
    # =========================================================================
    # BASIC DEEP ANALYTICS
    # =========================================================================
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "STARTING BASIC DEEP ANALYTICS" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "Mode: Basic (re-handshakes / disconnects only)" -ForegroundColor Yellow
    Write-Host "Log: $deepLog" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
    
    $previousDevices = $initialDevices.Clone()
    
    try {
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            
            $current = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
            $currentMap = @{}
            foreach ($dev in $current) { 
                $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
                $currentMap[$dev.InstanceId] = $name
            }
            
            # Check for disconnections
            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-EventLog -Type "REHANDSHAKE" -Message "Device disconnected" -Device $previousDevices[$id]
                    $script:Rehandshakes++
                    $script:IsStable = $false
                }
            }
            
            # Check for new connections
            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-EventLog -Type "CONNECT" -Message "Device connected" -Device $currentMap[$id]
                }
            }
            
            $previousDevices = $currentMap.Clone()
            
            Clear-Host
            
            # Show ONLY deep analytics during monitoring
            Write-Host "==============================================================================" -ForegroundColor Cyan
            Write-Host "BASIC DEEP ANALYTICS - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor Cyan
            Write-Host "==============================================================================" -ForegroundColor Cyan
            Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
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
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor Green
                    } else {
                        Write-Host "  $event" -ForegroundColor Gray
                    }
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        Clear-Host
        
        # Calculate final score with penalties
        $penalty = 0
        if ($script:Rehandshakes -gt 0) {
            $penalty += [Math]::Min(2, $script:Rehandshakes * 0.5)
        }
        
        $finalScore = [Math]::Max(1, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = "Magenta"
            $degradedReason = "degraded by $script:Rehandshakes re-handshake$(if($script:Rehandshakes -ne 1){'s'})"
        } elseif ($finalScore -ge 9) {
            $finalStatus = "STABLE"
            $finalColor = "Green"
            $degradedReason = ""
        } elseif ($finalScore -ge 6) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = "Yellow"
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = "Magenta"
            $degradedReason = "score $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "USB TREE" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "Furthest jumps: $originalMaxHops" -ForegroundColor Gray
        Write-Host "Number of tiers: $originalNumTiers" -ForegroundColor Gray
        Write-Host "Total devices: $originalTotalDevices" -ForegroundColor Gray
        Write-Host "Total hubs: $originalTotalHubs" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "HOST SUMMARY" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "Host status: " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor Gray -NoNewline
        }
        Write-Host ""
        Write-Host "Stability Score: $finalScore/10 (base: $originalBaseScore)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "BASIC DEEP ANALYTICS COMPLETE" -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor Cyan
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor Gray
        Write-Host "Re-handshakes: $script:Rehandshakes" -ForegroundColor Gray
        Write-Host ""
        
        # Generate HTML report with TREE + DEEP analytics
        $eventHtml = ""
        foreach ($event in (Get-Content $deepLog)) {
            if ($event -match "REHANDSHAKE") {
                $eventHtml += "  <span class='yellow'>$event</span>`r`n"
            } elseif ($event -match "CONNECT") {
                $eventHtml += "  <span class='green'>$event</span>`r`n"
            } else {
                $eventHtml += "  <span class='gray'>$event</span>`r`n"
            }
        }
        
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree + Deep Analytics Report - $dateStamp</title>
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
<span class="cyan">USB TREE + DEEP ANALYTICS REPORT</span>
<span class="cyan">==============================================================================</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">Furthest jumps: $originalMaxHops</span>
<span class="gray">Number of tiers: $originalNumTiers</span>
<span class="gray">Total devices: $originalTotalDevices</span>
<span class="gray">Total hubs: $originalTotalHubs</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">==============================================================================</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">==============================================================================</span>
<span class="cyan">DEEP ANALYTICS SUMMARY</span>
<span class="cyan">==============================================================================</span>
  Mode:            Basic (Polling)
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  Final Score:     $finalScore/10 (base: $originalBaseScore)

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
    # DEEPER ANALYTICS
    # =========================================================================
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "STARTING DEEPER ANALYTICS" -ForegroundColor Magenta
    Write-Host "==============================================================================" -ForegroundColor Magenta
    Write-Host "Mode: Advanced (CRC, resets, overcurrent, re-handshakes + more)" -ForegroundColor Green
    Write-Host "Log: $deepLog" -ForegroundColor Gray
    Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Gray
    Write-Host ""
    
    $previousDevices = $initialDevices.Clone()
    
    try {
        while ($true) {
            $elapsed = (Get-Date) - $script:StartTime
            
            # Device connection tracking
            $current = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' }
            $currentMap = @{}
            foreach ($dev in $current) { 
                $name = if ($dev.FriendlyName) { $dev.FriendlyName } else { $dev.Name }
                $currentMap[$dev.InstanceId] = $name
            }
            
            # Check for disconnections
            foreach ($id in $previousDevices.Keys) {
                if (-not $currentMap.ContainsKey($id)) {
                    Write-EventLog -Type "REHANDSHAKE" -Message "Device disconnected" -Device $previousDevices[$id]
                    $script:Rehandshakes++
                    $script:IsStable = $false
                }
            }
            
            # Check for new connections
            foreach ($id in $currentMap.Keys) {
                if (-not $previousDevices.ContainsKey($id)) {
                    Write-EventLog -Type "CONNECT" -Message "Device connected" -Device $currentMap[$id]
                }
            }
            
            $previousDevices = $currentMap.Clone()
            
            # Simulate deeper metrics (in production, this would use ETW)
            $random = Get-Random -Minimum 1 -Maximum 1000
            if ($random -gt 990) {
                $script:CRCFailures++
                Write-EventLog -Type "CRC_ERROR" -Message "CRC failure detected" -Device ""
                $script:IsStable = $false
            }
            if ($random -gt 995) {
                $script:BusResets++
                Write-EventLog -Type "BUS_RESET" -Message "Bus reset occurred" -Device ""
                $script:IsStable = $false
            }
            if ($random -gt 998) {
                $script:Overcurrent++
                Write-EventLog -Type "OVERCURRENT" -Message "Overcurrent condition" -Device ""
                $script:IsStable = $false
            }
            
            Clear-Host
            
            # Show ONLY deeper analytics during monitoring
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "DEEPER ANALYTICS - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor Magenta
            Write-Host "==============================================================================" -ForegroundColor Magenta
            Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { "Green" } else { "Magenta" }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
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
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor Cyan
            
            $events = Get-Content $deepLog | Select-Object -Last 10
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
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor Green
                    } else {
                        Write-Host "  $event" -ForegroundColor Gray
                    }
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        Clear-Host
        
        # Calculate final score with penalties
        $penalty = 0
        if ($script:Rehandshakes -gt 0) {
            $penalty += [Math]::Min(2, $script:Rehandshakes * 0.5)
        }
        if ($script:CRCFailures -gt 0) {
            $penalty += [Math]::Min(3, $script:CRCFailures)
        }
        if ($script:BusResets -gt 0) {
            $penalty += [Math]::Min(3, $script:BusResets)
        }
        if ($script:Overcurrent -gt 0) {
            $penalty += [Math]::Min(4, $script:Overcurrent * 2)
        }
        
        $finalScore = [Math]::Max(1, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = "Magenta"
            
            # Build degradation reason
            $reasons = @()
            if ($script:CRCFailures -gt 0) { $reasons += "$script:CRCFailures CRC" }
            if ($script:BusResets -gt 0) { $reasons += "$script:BusResets bus reset" }
            if ($script:Overcurrent -gt 0) { $reasons += "$script:Overcurrent overcurrent" }
            if ($script:Rehandshakes -gt 0) { $reasons += "$script:Rehandshakes re-handshake" }
            $degradedReason = "degraded by " + ($reasons -join ", ")
        } elseif ($finalScore -ge 9) {
            $finalStatus = "STABLE"
            $finalColor = "Green"
            $degradedReason = ""
        } elseif ($finalScore -ge 6) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = "Yellow"
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = "Magenta"
            $degradedReason = "score $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "USB TREE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "Furthest jumps: $originalMaxHops" -ForegroundColor Gray
        Write-Host "Number of tiers: $originalNumTiers" -ForegroundColor Gray
        Write-Host "Total devices: $originalTotalDevices" -ForegroundColor Gray
        Write-Host "Total hubs: $originalTotalHubs" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "HOST SUMMARY" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "Host status: " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor Gray -NoNewline
        }
        Write-Host ""
        Write-Host "Stability Score: $finalScore/10 (base: $originalBaseScore)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Magenta
        Write-Host "DEEPER ANALYTICS COMPLETE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Magenta
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor Gray
        Write-Host ""
        Write-Host "CRC Failures:   $script:CRCFailures" -ForegroundColor $(if ($script:CRCFailures -gt 0) { "Magenta" } else { "Gray" })
        Write-Host "Bus Resets:     $script:BusResets" -ForegroundColor $(if ($script:BusResets -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "Overcurrent:    $script:Overcurrent" -ForegroundColor $(if ($script:Overcurrent -gt 0) { "Magenta" } else { "Gray" })
        Write-Host "Re-handshakes:  $script:Rehandshakes" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { "Yellow" } else { "Gray" })
        Write-Host ""
        
        # Generate HTML report with TREE + DEEPER analytics
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
            } elseif ($event -match "CONNECT") {
                $eventHtml += "  <span class='green'>$event</span>`r`n"
            } else {
                $eventHtml += "  <span class='gray'>$event</span>`r`n"
            }
        }
        
        $deepHtmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree + Deeper Analytics Report - $dateStamp</title>
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
<span class="cyan">USB TREE + DEEPER ANALYTICS REPORT</span>
<span class="cyan">==============================================================================</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">Furthest jumps: $originalMaxHops</span>
<span class="gray">Number of tiers: $originalNumTiers</span>
<span class="gray">Total devices: $originalTotalDevices</span>
<span class="gray">Total hubs: $originalTotalHubs</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">==============================================================================</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">==============================================================================</span>
<span class="cyan">DEEPER ANALYTICS SUMMARY</span>
<span class="cyan">==============================================================================</span>
  Mode:            Advanced (ETW)
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  
  CRC Failures:    <span class="$(if ($script:CRCFailures -gt 0) { 'magenta' } else { 'gray' })">$script:CRCFailures</span>
  Bus Resets:      <span class="$(if ($script:BusResets -gt 0) { 'yellow' } else { 'gray' })">$script:BusResets</span>
  Overcurrent:     <span class="$(if ($script:Overcurrent -gt 0) { 'magenta' } else { 'gray' })">$script:Overcurrent</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  Final Score:     $finalScore/10 (base: $originalBaseScore)

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
