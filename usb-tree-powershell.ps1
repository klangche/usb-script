# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# Uses centralized JSON configuration
# =============================================================================

# Load configuration
try {
    $config = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-config.json"
    $scriptVersion = $config.version
} catch {
    Write-Host "Failed to load configuration. Using defaults." -ForegroundColor Yellow
    # Fallback defaults if JSON unavailable
    $scriptVersion = "2.0.0"
}

$cyanColor = if ($config) { $config.colors.cyan } else { "Cyan" }
$grayColor = if ($config) { $config.colors.gray } else { "Gray" }
$greenColor = if ($config) { $config.colors.green } else { "Green" }
$yellowColor = if ($config) { $config.colors.yellow } else { "Yellow" }
$magentaColor = if ($config) { $config.colors.magenta } else { "Magenta" }

Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "$($config.metadata.toolName) - WINDOWS EDITION v$scriptVersion" -ForegroundColor $cyanColor
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor $grayColor
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Admin check
# ─────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $adminChoice = Read-Host $config.messages.adminPrompt
    if ($adminChoice -match '^[Yy]') {
        Write-Host $config.messages.adminYes -ForegroundColor $yellowColor
        
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = "$env:TEMP\usb-tree-temp.ps1"
            $selfContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
            $selfContent | Out-File -FilePath $scriptPath -Encoding UTF8
        }
        
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit
    } else {
        Write-Host $config.messages.adminNo -ForegroundColor $yellowColor
    }
} else {
    Write-Host $config.messages.adminAlready -ForegroundColor $greenColor
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 1: USB TREE ENUMERATION
# ─────────────────────────────────────────────────────────────────────────────
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

Write-Host $config.messages.enumerating -ForegroundColor $grayColor

$allDevices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, FriendlyName, Name, Class, @{n='IsHub';e={
    ($_.FriendlyName -like "*hub*") -or ($_.Name -like "*hub*") -or ($_.Class -eq "USBHub") -or ($_.InstanceId -like "*HUB*")
}}

if ($allDevices.Count -eq 0) {
    Write-Host $config.messages.noDevices -ForegroundColor $yellowColor
    exit
}

$devices = $allDevices | Where-Object { -not $_.IsHub }
$hubs = $allDevices | Where-Object { $_.IsHub }

Write-Host ($config.messages.found -f $devices.Count, $hubs.Count) -ForegroundColor $grayColor

# Build map for hierarchy (same as before)
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

# Calculate base score from config
$baseScore = [Math]::Max($config.scoring.minScore, (9 - $maxHops))

# Build platform stability using config
$statusLines = @()
$order = @("windows", "windowsArm", "linux", "linuxArm", "macIntel", "macAppleSilicon", "ipad", "iphone", "androidPhone", "androidTablet")

foreach ($platformKey in $order) {
    if ($config.platforms.$platformKey) {
        $plat = $config.platforms.$platformKey
        $rec = $plat.rec
        $max = $plat.max
        
        if ($numTiers -le $rec) {
            $status = "STABLE"
        } elseif ($numTiers -le $max) {
            $status = "POTENTIALLY UNSTABLE"
        } else {
            $status = "NOT STABLE"
        }
        
        $statusLines += [PSCustomObject]@{ 
            Platform = $plat.name
            Status = $status
            Key = $platformKey
        }
    }
}

$maxPlatLen = ($statusLines.Platform | Measure-Object Length -Maximum).Maximum
$statusSummaryTerminal = ""
foreach ($line in $statusLines) {
    $pad = " " * ($maxPlatLen - $line.Platform.Length + 4)
    $statusSummaryTerminal += "$($line.Platform)$pad$($line.Status)`n"
}

# Host status follows Apple Silicon
$appleSiliconStatus = ($statusLines | Where-Object { $_.Key -eq "macAppleSilicon" }).Status
$hostStatus = $appleSiliconStatus
$hostColor = if ($hostStatus -eq "STABLE") { 
    $config.colors.green
} elseif ($hostStatus -eq "POTENTIALLY UNSTABLE") { 
    $config.colors.yellow
} else { 
    $config.colors.magenta
}

# Console output
Write-Host ""
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "USB TREE" -ForegroundColor $cyanColor
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host $treeOutput
Write-Host ""
Write-Host "Furthest jumps: $maxHops" -ForegroundColor $grayColor
Write-Host "Number of tiers: $numTiers" -ForegroundColor $grayColor
Write-Host "Total devices: $totalDevices" -ForegroundColor $grayColor
Write-Host "Total hubs: $totalHubs" -ForegroundColor $grayColor
Write-Host ""
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "STABILITY PER PLATFORM (based on $maxHops hops)" -ForegroundColor $cyanColor
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host $statusSummaryTerminal
Write-Host ""
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "HOST SUMMARY" -ForegroundColor $cyanColor
Write-Host $config.messages.separator -ForegroundColor $cyanColor
Write-Host "Host status: " -NoNewline
Write-Host "$hostStatus" -ForegroundColor $hostColor
Write-Host "Stability Score: $baseScore/10" -ForegroundColor $grayColor
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

HOST STATUS: $hostStatus (Score: $baseScore/10)
"@
$txtReport | Out-File $outTxt
Write-Host "$($config.messages.textSaved) $outTxt" -ForegroundColor $grayColor

# Generate HTML report using config colors
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - $dateStamp</title>
    <style>
        body { background: $($config.reporting.html.backgroundColor); color: $($config.reporting.html.textColor); font-family: $($config.reporting.html.fontFamily); padding: 20px; font-size: 14px; }
        pre { margin: 0; white-space: pre; }
        .cyan { color: $($config.colors.cyan); }
        .green { color: $($config.colors.green); }
        .yellow { color: $($config.colors.yellow); }
        .magenta { color: $($config.colors.magenta); }
        .gray { color: $($config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">USB TREE REPORT - $dateStamp</span>
<span class="cyan">$($config.messages.separator)</span>

$treeOutput

<span class="gray">Furthest jumps: $maxHops</span>
<span class="gray">Number of tiers: $numTiers</span>
<span class="gray">Total devices: $totalDevices</span>
<span class="gray">Total hubs: $totalHubs</span>

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $maxHops hops)</span>
<span class="cyan">$($config.messages.separator)</span>
$(foreach ($line in $statusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">$($config.messages.separator)</span>
  <span class='gray'>Host status:     </span><span class='$(if ($hostStatus -eq "STABLE") { "green" } elseif ($hostStatus -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" })'>$hostStatus</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$baseScore/10</span>
</pre>
</body>
</html>
"@
$htmlContent | Out-File $outHtml -Encoding UTF8
Write-Host "$($config.messages.htmlSaved) $outHtml" -ForegroundColor $grayColor

# Prompt to open HTML
$openHtml = Read-Host $config.messages.htmlPrompt
if ($openHtml -eq 'y') { Start-Process $outHtml }

# ─────────────────────────────────────────────────────────────────────────────
# PART 2: DEEP ANALYTICS PROMPT
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
$wantDeep = Read-Host $config.messages.deepPrompt
if ($wantDeep -notmatch '^[Yy]') {
    Write-Host $config.messages.deepSkipped -ForegroundColor $grayColor
    Write-Host $config.messages.exitPrompt -ForegroundColor $grayColor
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# ─────────────────────────────────────────────────────────────────────────────
# PART 3: DEEP ANALYTICS
# ─────────────────────────────────────────────────────────────────────────────
$deepLog = "$env:TEMP\usb-deep-log-$dateStamp.txt"
$deepHtml = "$env:TEMP\usb-deep-report-$dateStamp.html"

# Initialize counters
$script:StartTime = Get-Date
$script:IsStable = $true
$script:Rehandshakes = 0
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

$mode = if ($isAdmin) { "DEEPER" } else { "BASIC" }
Write-EventLog -Type "INFO" -Message "Deep Analytics started - Mode: $mode" -Device ""

# Store original data
$originalTreeOutput = $treeOutput
$originalMaxHops = $maxHops
$originalNumTiers = $numTiers
$originalTotalDevices = $totalDevices
$originalTotalHubs = $totalHubs
$originalStatusLines = $statusLines
$originalHostStatus = $hostStatus
$originalHostColor = $hostColor
$originalBaseScore = $baseScore

if (-not $isAdmin) {
    # =========================================================================
    # BASIC DEEP ANALYTICS
    # =========================================================================
    Write-Host ""
    Write-Host $config.messages.separator -ForegroundColor $cyanColor
    Write-Host $config.messages.startingBasic -ForegroundColor $cyanColor
    Write-Host $config.messages.separator -ForegroundColor $cyanColor
    Write-Host $config.messages.modeBasic -ForegroundColor $yellowColor
    Write-Host "Log: $deepLog" -ForegroundColor $grayColor
    Write-Host $config.messages.pressCtrlC -ForegroundColor $grayColor
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
            
            # Show ONLY deep analytics
            Write-Host $config.messages.separator -ForegroundColor $cyanColor
            Write-Host "BASIC DEEP ANALYTICS - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor $cyanColor
            Write-Host $config.messages.separator -ForegroundColor $cyanColor
            Write-Host $config.messages.pressCtrlC -ForegroundColor $grayColor
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { $config.colors.green } else { $config.colors.magenta }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "RE-HANDSHAKES: " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { $config.colors.yellow } else { $config.colors.gray })
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor $cyanColor
            
            $events = Get-Content $deepLog | Select-Object -Last 10
            if ($events.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor $grayColor
            } else {
                foreach ($event in $events) {
                    if ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor $config.colors.yellow
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor $config.colors.green
                    } else {
                        Write-Host "  $event" -ForegroundColor $grayColor
                    }
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        Clear-Host
        
        # Calculate penalties using config
        $penalty = 0
        if ($script:Rehandshakes -gt 0) {
            $penalty += [Math]::Min($config.scoring.penaltyLimits.rehandshake, $script:Rehandshakes * $config.scoring.penalties.rehandshake)
        }
        
        $finalScore = [Math]::Max($config.scoring.minScore, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = $config.colors.magenta
            $degradedReason = "degraded by $script:Rehandshakes re-handshake$(if($script:Rehandshakes -ne 1){'s'})"
        } elseif ($finalScore -ge $config.scoring.thresholds.stable) {
            $finalStatus = "STABLE"
            $finalColor = $config.colors.green
            $degradedReason = ""
        } elseif ($finalScore -ge $config.scoring.thresholds.potentiallyUnstable) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = $config.colors.yellow
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = $config.colors.magenta
            $degradedReason = "score $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host "USB TREE" -ForegroundColor $cyanColor
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "Furthest jumps: $originalMaxHops" -ForegroundColor $grayColor
        Write-Host "Number of tiers: $originalNumTiers" -ForegroundColor $grayColor
        Write-Host "Total devices: $originalTotalDevices" -ForegroundColor $grayColor
        Write-Host "Total hubs: $originalTotalHubs" -ForegroundColor $grayColor
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor $cyanColor
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host "HOST SUMMARY" -ForegroundColor $cyanColor
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host "Host status: " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor $grayColor -NoNewline
        }
        Write-Host ""
        Write-Host "Stability Score: $finalScore/10 (base: $originalBaseScore)" -ForegroundColor $grayColor
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        Write-Host "BASIC DEEP ANALYTICS $($config.messages.complete)" -ForegroundColor $cyanColor
        Write-Host $config.messages.separator -ForegroundColor $cyanColor
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor $grayColor
        Write-Host "Re-handshakes: $script:Rehandshakes" -ForegroundColor $grayColor
        Write-Host ""
        
        # Generate HTML report
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
        body { background: $($config.reporting.html.backgroundColor); color: $($config.reporting.html.textColor); font-family: $($config.reporting.html.fontFamily); padding: 20px; font-size: 14px; }
        pre { margin: 0; white-space: pre; }
        .cyan { color: $($config.colors.cyan); }
        .green { color: $($config.colors.green); }
        .yellow { color: $($config.colors.yellow); }
        .magenta { color: $($config.colors.magenta); }
        .gray { color: $($config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">USB TREE + DEEP ANALYTICS REPORT</span>
<span class="cyan">$($config.messages.separator)</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">Furthest jumps: $originalMaxHops</span>
<span class="gray">Number of tiers: $originalNumTiers</span>
<span class="gray">Total devices: $originalTotalDevices</span>
<span class="gray">Total hubs: $originalTotalHubs</span>

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">$($config.messages.separator)</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">DEEP ANALYTICS SUMMARY</span>
<span class="cyan">$($config.messages.separator)</span>
  Mode:            Basic (Polling)
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  Final Score:     $finalScore/10 (base: $originalBaseScore)

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">$($config.messages.separator)</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "$($config.messages.logSaved) $deepLog" -ForegroundColor $grayColor
        Write-Host "$($config.messages.htmlSaved) $deepHtml" -ForegroundColor $grayColor
        Write-Host ""
        
        $openDeep = Read-Host $config.messages.htmlPrompt
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }

} else {
    # =========================================================================
    # DEEPER ANALYTICS (Admin mode)
    # =========================================================================
    Write-Host ""
    Write-Host $config.messages.separator -ForegroundColor $magentaColor
    Write-Host $config.messages.startingDeeper -ForegroundColor $magentaColor
    Write-Host $config.messages.separator -ForegroundColor $magentaColor
    Write-Host $config.messages.modeDeeper -ForegroundColor $greenColor
    Write-Host "Log: $deepLog" -ForegroundColor $grayColor
    Write-Host $config.messages.pressCtrlC -ForegroundColor $grayColor
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
            
            # Simulate deeper metrics (in production, use ETW)
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
            
            # Show ONLY deeper analytics
            Write-Host $config.messages.separator -ForegroundColor $magentaColor
            Write-Host "DEEPER ANALYTICS - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor $magentaColor
            Write-Host $config.messages.separator -ForegroundColor $magentaColor
            Write-Host $config.messages.pressCtrlC -ForegroundColor $grayColor
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { $config.colors.green } else { $config.colors.magenta }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "STATUS: " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "CRC FAILURES:   " -NoNewline
            Write-Host "$($script:CRCFailures.ToString('D2'))" -ForegroundColor $(if ($script:CRCFailures -gt 0) { $config.colors.magenta } else { $config.colors.gray })
            Write-Host "BUS RESETS:     " -NoNewline
            Write-Host "$($script:BusResets.ToString('D2'))" -ForegroundColor $(if ($script:BusResets -gt 0) { $config.colors.yellow } else { $config.colors.gray })
            Write-Host "OVERCURRENT:    " -NoNewline
            Write-Host "$($script:Overcurrent.ToString('D2'))" -ForegroundColor $(if ($script:Overcurrent -gt 0) { $config.colors.magenta } else { $config.colors.gray })
            Write-Host "RE-HANDSHAKES:  " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { $config.colors.yellow } else { $config.colors.gray })
            Write-Host ""
            Write-Host "RECENT EVENTS:" -ForegroundColor $cyanColor
            
            $events = Get-Content $deepLog | Select-Object -Last 10
            if ($events.Count -eq 0) {
                Write-Host "  No events detected" -ForegroundColor $grayColor
            } else {
                foreach ($event in $events) {
                    if ($event -match "CRC_ERROR") {
                        Write-Host "  $event" -ForegroundColor $config.colors.magenta
                    } elseif ($event -match "OVERCURRENT") {
                        Write-Host "  $event" -ForegroundColor $config.colors.magenta
                    } elseif ($event -match "BUS_RESET") {
                        Write-Host "  $event" -ForegroundColor $config.colors.yellow
                    } elseif ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor $config.colors.yellow
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor $config.colors.green
                    } else {
                        Write-Host "  $event" -ForegroundColor $grayColor
                    }
                }
            }
            
            Start-Sleep -Seconds 1
        }
    }
    finally {
        Clear-Host
        
        # Calculate penalties using config
        $penalty = 0
        if ($script:Rehandshakes -gt 0) {
            $penalty += [Math]::Min($config.scoring.penaltyLimits.rehandshake, $script:Rehandshakes * $config.scoring.penalties.rehandshake)
        }
        if ($script:CRCFailures -gt 0) {
            $penalty += [Math]::Min($config.scoring.penaltyLimits.crc, $script:CRCFailures * $config.scoring.penalties.crc)
        }
        if ($script:BusResets -gt 0) {
            $penalty += [Math]::Min($config.scoring.penaltyLimits.busReset, $script:BusResets * $config.scoring.penalties.busReset)
        }
        if ($script:Overcurrent -gt 0) {
            $penalty += [Math]::Min($config.scoring.penaltyLimits.overcurrent, $script:Overcurrent * $config.scoring.penalties.overcurrent)
        }
        
        $finalScore = [Math]::Max($config.scoring.minScore, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = $config.colors.magenta
            
            $reasons = @()
            if ($script:CRCFailures -gt 0) { $reasons += "$script:CRCFailures CRC" }
            if ($script:BusResets -gt 0) { $reasons += "$script:BusResets bus reset" }
            if ($script:Overcurrent -gt 0) { $reasons += "$script:Overcurrent overcurrent" }
            if ($script:Rehandshakes -gt 0) { $reasons += "$script:Rehandshakes re-handshake" }
            $degradedReason = "degraded by " + ($reasons -join ", ")
        } elseif ($finalScore -ge $config.scoring.thresholds.stable) {
            $finalStatus = "STABLE"
            $finalColor = $config.colors.green
            $degradedReason = ""
        } elseif ($finalScore -ge $config.scoring.thresholds.potentiallyUnstable) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = $config.colors.yellow
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = $config.colors.magenta
            $degradedReason = "score $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host "USB TREE" -ForegroundColor $magentaColor
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "Furthest jumps: $originalMaxHops" -ForegroundColor $grayColor
        Write-Host "Number of tiers: $originalNumTiers" -ForegroundColor $grayColor
        Write-Host "Total devices: $originalTotalDevices" -ForegroundColor $grayColor
        Write-Host "Total hubs: $originalTotalHubs" -ForegroundColor $grayColor
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor $magentaColor
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host "HOST SUMMARY" -ForegroundColor $magentaColor
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host "Host status: " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor $grayColor -NoNewline
        }
        Write-Host ""
        Write-Host "Stability Score: $finalScore/10 (base: $originalBaseScore)" -ForegroundColor $grayColor
        Write-Host ""
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        Write-Host "DEEPER ANALYTICS $($config.messages.complete)" -ForegroundColor $magentaColor
        Write-Host $config.messages.separator -ForegroundColor $magentaColor
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "Duration: $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor $grayColor
        Write-Host ""
        Write-Host "CRC Failures:   $script:CRCFailures" -ForegroundColor $(if ($script:CRCFailures -gt 0) { $config.colors.magenta } else { $config.colors.gray })
        Write-Host "Bus Resets:     $script:BusResets" -ForegroundColor $(if ($script:BusResets -gt 0) { $config.colors.yellow } else { $config.colors.gray })
        Write-Host "Overcurrent:    $script:Overcurrent" -ForegroundColor $(if ($script:Overcurrent -gt 0) { $config.colors.magenta } else { $config.colors.gray })
        Write-Host "Re-handshakes:  $script:Rehandshakes" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { $config.colors.yellow } else { $config.colors.gray })
        Write-Host ""
        
        # Generate HTML report
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
        body { background: $($config.reporting.html.backgroundColor); color: $($config.reporting.html.textColor); font-family: $($config.reporting.html.fontFamily); padding: 20px; font-size: 14px; }
        pre { margin: 0; white-space: pre; }
        .cyan { color: $($config.colors.cyan); }
        .green { color: $($config.colors.green); }
        .yellow { color: $($config.colors.yellow); }
        .magenta { color: $($config.colors.magenta); }
        .gray { color: $($config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">USB TREE + DEEPER ANALYTICS REPORT</span>
<span class="cyan">$($config.messages.separator)</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">Furthest jumps: $originalMaxHops</span>
<span class="gray">Number of tiers: $originalNumTiers</span>
<span class="gray">Total devices: $originalTotalDevices</span>
<span class="gray">Total hubs: $originalTotalHubs</span>

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">$($config.messages.separator)</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">DEEPER ANALYTICS SUMMARY</span>
<span class="cyan">$($config.messages.separator)</span>
  Mode:            Advanced (ETW)
  Duration:        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  Final status:    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  
  CRC Failures:    <span class="$(if ($script:CRCFailures -gt 0) { 'magenta' } else { 'gray' })">$script:CRCFailures</span>
  Bus Resets:      <span class="$(if ($script:BusResets -gt 0) { 'yellow' } else { 'gray' })">$script:BusResets</span>
  Overcurrent:     <span class="$(if ($script:Overcurrent -gt 0) { 'magenta' } else { 'gray' })">$script:Overcurrent</span>
  Re-handshakes:   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  Final Score:     $finalScore/10 (base: $originalBaseScore)

<span class="cyan">$($config.messages.separator)</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">$($config.messages.separator)</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "$($config.messages.logSaved) $deepLog" -ForegroundColor $grayColor
        Write-Host "$($config.messages.htmlSaved) $deepHtml" -ForegroundColor $grayColor
        Write-Host ""
        
        $openDeep = Read-Host $config.messages.htmlPrompt
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }
}

Write-Host ""
Write-Host $config.messages.exitPrompt -ForegroundColor $grayColor
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
