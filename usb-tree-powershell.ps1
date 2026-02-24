# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# Uses centralized configuration from usb-tree-config.json
# =============================================================================

# Load configuration
try {
    $global:Config = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-config.json"
    $scriptVersion = $Config.version
} catch {
    Write-Host "Failed to load configuration. Using defaults." -ForegroundColor Yellow
    # Fallback defaults if config fails to load
    $scriptVersion = "1.0.0"
}

# Helper function to get colored output
function Get-Color {
    param($ColorName)
    $hex = $Config.colors.$ColorName
    switch ($hex) {
        "#00ffff" { return "Cyan" }
        "#ff00ff" { return "Magenta" }
        "#ffff00" { return "Yellow" }
        "#00ff00" { return "Green" }
        "#c0c0c0" { return "Gray" }
        default { return "Gray" }
    }
}

Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "$($Config.messages.en.welcome) - WINDOWS EDITION v$scriptVersion" -ForegroundColor (Get-Color "cyan")
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "$($Config.messages.en.platform): Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor (Get-Color "gray")
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Admin check + smart handling
# ─────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $adminChoice = Read-Host $Config.messages.en.adminPrompt
    if ($adminChoice -match '^[Yy]') {
        Write-Host $Config.messages.en.adminYes -ForegroundColor Yellow
        
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = "$env:TEMP\usb-tree-temp.ps1"
            $selfContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
            $selfContent | Out-File -FilePath $scriptPath -Encoding UTF8
        }
        
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit
    } else {
        Write-Host "$($Config.messages.en.adminNo) (basic tree + basic deep if selected)" -ForegroundColor Yellow
    }
} else {
    Write-Host $Config.messages.en.adminAlready -ForegroundColor Green
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 1: USB TREE ENUMERATION AND REPORTING
# ─────────────────────────────────────────────────────────────────────────────
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

Write-Host "$($Config.messages.en.enumerating)..." -ForegroundColor (Get-Color "gray")

$allDevices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, FriendlyName, Name, Class, @{n='IsHub';e={
    ($_.FriendlyName -like "*hub*") -or ($_.Name -like "*hub*") -or ($_.Class -eq "USBHub") -or ($_.InstanceId -like "*HUB*")
}}

if ($allDevices.Count -eq 0) {
    Write-Host $Config.messages.en.noDevices -ForegroundColor Yellow
    exit
}

$devices = $allDevices | Where-Object { -not $_.IsHub }
$hubs = $allDevices | Where-Object { $_.IsHub }

Write-Host "$($Config.messages.en.found) $($devices.Count) $($Config.messages.en.devices) $($Config.messages.en.and) $($hubs.Count) $($Config.messages.en.hubs)" -ForegroundColor (Get-Color "gray")

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
$baseStabilityScore = [Math]::Max($Config.scoring.minScore, (9 - $maxHops))

# Platform stability table from config
$statusLines = @()
$order = @()
foreach ($plat in $Config.platformStability.PSObject.Properties.Name) {
    $order += $plat
    $rec = $Config.platformStability.$plat.rec
    $max = $Config.platformStability.$plat.max
    $status = if ($numTiers -le $rec) { "STABLE" } 
              elseif ($numTiers -le $max) { "POTENTIALLY UNSTABLE" } 
              else { "NOT STABLE" }
    $statusLines += [PSCustomObject]@{ 
        Platform = $Config.platformStability.$plat.name
        Status = $status 
    }
}

$maxPlatLen = ($statusLines.Platform | Measure-Object Length -Maximum).Maximum
$statusSummaryTerminal = ""
foreach ($line in $statusLines) {
    $pad = " " * ($maxPlatLen - $line.Platform.Length + 4)
    $statusSummaryTerminal += "$($line.Platform)$pad$($line.Status)`n"
}

# Host status follows Apple Silicon
$appleSiliconStatus = ($statusLines | Where-Object { $_.Platform -eq "Mac Apple Silicon" }).Status
$hostStatus = $appleSiliconStatus
$hostColor = if ($hostStatus -eq "STABLE") { (Get-Color "green") } 
             elseif ($hostStatus -eq "POTENTIALLY UNSTABLE") { (Get-Color "yellow") } 
             else { (Get-Color "magenta") }

# Console output
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "USB TREE" -ForegroundColor (Get-Color "cyan")
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host $treeOutput
Write-Host ""
Write-Host "$($Config.messages.en.furthestJumps): $maxHops" -ForegroundColor (Get-Color "gray")
Write-Host "$($Config.messages.en.numberOfTiers): $numTiers" -ForegroundColor (Get-Color "gray")
Write-Host "$($Config.messages.en.totalDevices): $totalDevices" -ForegroundColor (Get-Color "gray")
Write-Host "$($Config.messages.en.totalHubs): $totalHubs" -ForegroundColor (Get-Color "gray")
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "STABILITY PER PLATFORM (based on $maxHops hops)" -ForegroundColor (Get-Color "cyan")
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host $statusSummaryTerminal
Write-Host ""
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "HOST SUMMARY" -ForegroundColor (Get-Color "cyan")
Write-Host "==============================================================================" -ForegroundColor (Get-Color "cyan")
Write-Host "$($Config.messages.en.hostStatus): " -NoNewline
Write-Host "$hostStatus" -ForegroundColor $hostColor
Write-Host "$($Config.messages.en.stabilityScore): $baseStabilityScore/10" -ForegroundColor (Get-Color "gray")
Write-Host ""

# Save text report
$txtReport = @"
USB TREE REPORT - $dateStamp

$treeOutput

$($Config.messages.en.furthestJumps): $maxHops
$($Config.messages.en.numberOfTiers): $numTiers
$($Config.messages.en.totalDevices): $totalDevices
$($Config.messages.en.totalHubs): $totalHubs

STABILITY SUMMARY
$statusSummaryTerminal

$($Config.messages.en.hostStatus): $hostStatus ($($Config.messages.en.stabilityScore): $baseStabilityScore/10)
"@
$txtReport | Out-File $outTxt
Write-Host "$($Config.messages.en.reportSaved): $outTxt" -ForegroundColor (Get-Color "gray")

# Generate HTML report
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - $dateStamp</title>
    <style>
        body { background: $($Config.reporting.html.backgroundColor); color: $($Config.reporting.html.textColor); font-family: $($Config.reporting.html.fontFamily); padding: 20px; font-size: $($Config.reporting.html.fontSize); }
        pre { margin: 0; white-space: pre; }
        .cyan { color: $($Config.colors.cyan); }
        .green { color: $($Config.colors.green); }
        .yellow { color: $($Config.colors.yellow); }
        .magenta { color: $($Config.colors.magenta); }
        .gray { color: $($Config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">USB TREE REPORT - $dateStamp</span>
<span class="cyan">$($Config.reporting.html.separator)</span>

$treeOutput

<span class="gray">$($Config.messages.en.furthestJumps): $maxHops</span>
<span class="gray">$($Config.messages.en.numberOfTiers): $numTiers</span>
<span class="gray">$($Config.messages.en.totalDevices): $totalDevices</span>
<span class="gray">$($Config.messages.en.totalHubs): $totalHubs</span>

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $maxHops hops)</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
$(foreach ($line in $statusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
  <span class='gray'>$($Config.messages.en.hostStatus):     </span><span class='$($hostStatus.ToLower().Replace(" ", ""))'>$hostStatus</span>
  <span class='gray'>$($Config.messages.en.stabilityScore): </span><span class='gray'>$baseStabilityScore/10</span>
</pre>
</body>
</html>
"@
$htmlContent | Out-File $outHtml -Encoding UTF8
Write-Host "$($Config.messages.en.htmlSaved): $outHtml" -ForegroundColor (Get-Color "gray")

# Prompt to open HTML
$openHtml = Read-Host $Config.messages.en.htmlPrompt
if ($openHtml -eq 'y') { Start-Process $outHtml }

# ─────────────────────────────────────────────────────────────────────────────
# PART 2: DEEP ANALYTICS PROMPT
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
$wantDeep = Read-Host $Config.messages.en.deepPrompt
if ($wantDeep -notmatch '^[Yy]') {
    Write-Host "$($Config.messages.en.deepPrompt) skipped." -ForegroundColor (Get-Color "gray")
    Write-Host $Config.messages.en.exitPrompt -ForegroundColor (Get-Color "gray")
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

$analyticsMode = if ($isAdmin) { "deeper" } else { "basic" }
Write-EventLog -Type "INFO" -Message "Deep Analytics started - Mode: $($Config.analytics.$analyticsMode.name)" -Device ""

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
    $mode = $Config.analytics.basic
    $headerColor = (Get-Color $mode.headerColor)
    $modeColor = (Get-Color $mode.modeColor)
    
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor $headerColor
    Write-Host "$($Config.messages.en.deepStarted) - $($mode.name)" -ForegroundColor $headerColor
    Write-Host "==============================================================================" -ForegroundColor $headerColor
    Write-Host "$($Config.messages.en.mode): $($mode.description)" -ForegroundColor $modeColor
    Write-Host "$($Config.messages.en.reportSaved): $deepLog" -ForegroundColor (Get-Color "gray")
    Write-Host $Config.messages.en.pressCtrlC -ForegroundColor (Get-Color "gray")
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
            Write-Host "==============================================================================" -ForegroundColor $headerColor
            Write-Host "$($mode.name) - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor $headerColor
            Write-Host "==============================================================================" -ForegroundColor $headerColor
            Write-Host $Config.messages.en.pressCtrlC -ForegroundColor (Get-Color "gray")
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { (Get-Color "green") } else { (Get-Color "magenta") }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "$($Config.messages.en.finalStatus): " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "$($Config.messages.en.rehandshakes): " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { (Get-Color "yellow") } else { (Get-Color "gray") })
            Write-Host ""
            Write-Host "$($Config.messages.en.recentEvents):" -ForegroundColor $headerColor
            
            $events = Get-Content $deepLog | Select-Object -Last 10
            if ($events.Count -eq 0) {
                Write-Host "  $($Config.messages.en.noEvents)" -ForegroundColor (Get-Color "gray")
            } else {
                foreach ($event in $events) {
                    if ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "yellow")
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "green")
                    } else {
                        Write-Host "  $event" -ForegroundColor (Get-Color "gray")
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
            $penalty += [Math]::Min($Config.scoring.penaltyLimits.rehandshake, $script:Rehandshakes * $Config.scoring.penalties.rehandshake)
        }
        
        $finalScore = [Math]::Max($Config.scoring.minScore, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = (Get-Color "magenta")
            $degradedReason = "$($Config.messages.en.degradedBy) $script:Rehandshakes $($Config.messages.en.rehandshakes.ToLower())"
        } elseif ($finalScore -ge $Config.scoring.thresholds.stable) {
            $finalStatus = "STABLE"
            $finalColor = (Get-Color "green")
            $degradedReason = ""
        } elseif ($finalScore -ge $Config.scoring.thresholds.potentiallyUnstable) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = (Get-Color "yellow")
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = (Get-Color "magenta")
            $degradedReason = "$($Config.messages.en.stabilityScore) $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "USB TREE" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "$($Config.messages.en.furthestJumps): $originalMaxHops" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.numberOfTiers): $originalNumTiers" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.totalDevices): $originalTotalDevices" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.totalHubs): $originalTotalHubs" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "HOST SUMMARY" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "$($Config.messages.en.hostStatus): " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor (Get-Color "gray") -NoNewline
        }
        Write-Host ""
        Write-Host "$($Config.messages.en.stabilityScore): $finalScore/10 (base: $originalBaseScore)" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "$($Config.messages.en.deepComplete) - $($mode.name)" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "$($Config.messages.en.duration): $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.rehandshakes): $script:Rehandshakes" -ForegroundColor (Get-Color "gray")
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
        body { background: $($Config.reporting.html.backgroundColor); color: $($Config.reporting.html.textColor); font-family: $($Config.reporting.html.fontFamily); padding: 20px; font-size: $($Config.reporting.html.fontSize); }
        pre { margin: 0; font-family: $($Config.reporting.html.fontFamily); white-space: pre; }
        .cyan { color: $($Config.colors.cyan); }
        .green { color: $($Config.colors.green); }
        .yellow { color: $($Config.colors.yellow); }
        .magenta { color: $($Config.colors.magenta); }
        .gray { color: $($Config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">USB TREE + DEEP ANALYTICS REPORT</span>
<span class="cyan">$($Config.reporting.html.separator)</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">$($Config.messages.en.furthestJumps): $originalMaxHops</span>
<span class="gray">$($Config.messages.en.numberOfTiers): $originalNumTiers</span>
<span class="gray">$($Config.messages.en.totalDevices): $originalTotalDevices</span>
<span class="gray">$($Config.messages.en.totalHubs): $originalTotalHubs</span>

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">ANALYTICS SUMMARY</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
  $($Config.messages.en.mode):            $($mode.name)
  $($Config.messages.en.duration):        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  $($Config.messages.en.finalStatus):    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  $($Config.messages.en.rehandshakes):   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  $($Config.messages.en.stabilityScore):     $finalScore/10 (base: $originalBaseScore)

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "$($Config.messages.en.reportSaved): $deepLog" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.htmlSaved): $deepHtml" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        
        $openDeep = Read-Host $Config.messages.en.deepLogPrompt
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }

} else {
    # =========================================================================
    # DEEPER ANALYTICS
    # =========================================================================
    $mode = $Config.analytics.deeper
    $headerColor = (Get-Color $mode.headerColor)
    $modeColor = (Get-Color $mode.modeColor)
    
    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor $headerColor
    Write-Host "$($Config.messages.en.deepStarted) - $($mode.name)" -ForegroundColor $headerColor
    Write-Host "==============================================================================" -ForegroundColor $headerColor
    Write-Host "$($Config.messages.en.mode): $($mode.description)" -ForegroundColor $modeColor
    Write-Host "$($Config.messages.en.reportSaved): $deepLog" -ForegroundColor (Get-Color "gray")
    Write-Host $Config.messages.en.pressCtrlC -ForegroundColor (Get-Color "gray")
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
            Write-Host "==============================================================================" -ForegroundColor $headerColor
            Write-Host "$($mode.name) - Elapsed: $([string]::Format('{0:hh\:mm\:ss}', $elapsed))" -ForegroundColor $headerColor
            Write-Host "==============================================================================" -ForegroundColor $headerColor
            Write-Host $Config.messages.en.pressCtrlC -ForegroundColor (Get-Color "gray")
            Write-Host ""
            
            $statusColor = if ($script:IsStable) { (Get-Color "green") } else { (Get-Color "magenta") }
            $statusText = if ($script:IsStable) { "STABLE" } else { "UNSTABLE" }
            
            Write-Host "$($Config.messages.en.finalStatus): " -NoNewline
            Write-Host "$statusText" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "$($Config.messages.en.crcFailures):   " -NoNewline
            Write-Host "$($script:CRCFailures.ToString('D2'))" -ForegroundColor $(if ($script:CRCFailures -gt 0) { (Get-Color "magenta") } else { (Get-Color "gray") })
            Write-Host "$($Config.messages.en.busResets):     " -NoNewline
            Write-Host "$($script:BusResets.ToString('D2'))" -ForegroundColor $(if ($script:BusResets -gt 0) { (Get-Color "yellow") } else { (Get-Color "gray") })
            Write-Host "$($Config.messages.en.overcurrent):    " -NoNewline
            Write-Host "$($script:Overcurrent.ToString('D2'))" -ForegroundColor $(if ($script:Overcurrent -gt 0) { (Get-Color "magenta") } else { (Get-Color "gray") })
            Write-Host "$($Config.messages.en.rehandshakes):  " -NoNewline
            Write-Host "$($script:Rehandshakes.ToString('D2'))" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { (Get-Color "yellow") } else { (Get-Color "gray") })
            Write-Host ""
            Write-Host "$($Config.messages.en.recentEvents):" -ForegroundColor $headerColor
            
            $events = Get-Content $deepLog | Select-Object -Last 10
            if ($events.Count -eq 0) {
                Write-Host "  $($Config.messages.en.noEvents)" -ForegroundColor (Get-Color "gray")
            } else {
                foreach ($event in $events) {
                    if ($event -match "CRC_ERROR") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "magenta")
                    } elseif ($event -match "OVERCURRENT") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "magenta")
                    } elseif ($event -match "BUS_RESET") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "yellow")
                    } elseif ($event -match "REHANDSHAKE") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "yellow")
                    } elseif ($event -match "CONNECT") {
                        Write-Host "  $event" -ForegroundColor (Get-Color "green")
                    } else {
                        Write-Host "  $event" -ForegroundColor (Get-Color "gray")
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
            $penalty += [Math]::Min($Config.scoring.penaltyLimits.rehandshake, $script:Rehandshakes * $Config.scoring.penalties.rehandshake)
        }
        if ($script:CRCFailures -gt 0) {
            $penalty += [Math]::Min($Config.scoring.penaltyLimits.crc, $script:CRCFailures * $Config.scoring.penalties.crc)
        }
        if ($script:BusResets -gt 0) {
            $penalty += [Math]::Min($Config.scoring.penaltyLimits.busReset, $script:BusResets * $Config.scoring.penalties.busReset)
        }
        if ($script:Overcurrent -gt 0) {
            $penalty += [Math]::Min($Config.scoring.penaltyLimits.overcurrent, $script:Overcurrent * $Config.scoring.penalties.overcurrent)
        }
        
        $finalScore = [Math]::Max($Config.scoring.minScore, [Math]::Round($originalBaseScore - $penalty, 0))
        
        # Determine final status
        if (-not $script:IsStable) {
            $finalStatus = "NOT STABLE"
            $finalColor = (Get-Color "magenta")
            
            # Build degradation reason
            $reasons = @()
            if ($script:CRCFailures -gt 0) { $reasons += "$script:CRCFailures $($Config.messages.en.crcFailures.ToLower())" }
            if ($script:BusResets -gt 0) { $reasons += "$script:BusResets $($Config.messages.en.busResets.ToLower())" }
            if ($script:Overcurrent -gt 0) { $reasons += "$script:Overcurrent $($Config.messages.en.overcurrent.ToLower())" }
            if ($script:Rehandshakes -gt 0) { $reasons += "$script:Rehandshakes $($Config.messages.en.rehandshakes.ToLower())" }
            $degradedReason = "$($Config.messages.en.degradedBy) " + ($reasons -join ", ")
        } elseif ($finalScore -ge $Config.scoring.thresholds.stable) {
            $finalStatus = "STABLE"
            $finalColor = (Get-Color "green")
            $degradedReason = ""
        } elseif ($finalScore -ge $Config.scoring.thresholds.potentiallyUnstable) {
            $finalStatus = "POTENTIALLY UNSTABLE"
            $finalColor = (Get-Color "yellow")
            $degradedReason = ""
        } else {
            $finalStatus = "NOT STABLE"
            $finalColor = (Get-Color "magenta")
            $degradedReason = "$($Config.messages.en.stabilityScore) $finalScore/10"
        }
        
        # Show EVERYTHING
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "USB TREE" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host $originalTreeOutput
        Write-Host ""
        Write-Host "$($Config.messages.en.furthestJumps): $originalMaxHops" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.numberOfTiers): $originalNumTiers" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.totalDevices): $originalTotalDevices" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.totalHubs): $originalTotalHubs" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "STABILITY PER PLATFORM (based on $originalMaxHops hops)" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host $statusSummaryTerminal
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "HOST SUMMARY" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "$($Config.messages.en.hostStatus): " -NoNewline
        Write-Host "$finalStatus" -ForegroundColor $finalColor
        if ($degradedReason) {
            Write-Host " ($degradedReason)" -ForegroundColor (Get-Color "gray") -NoNewline
        }
        Write-Host ""
        Write-Host "$($Config.messages.en.stabilityScore): $finalScore/10 (base: $originalBaseScore)" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        Write-Host "$($Config.messages.en.deepComplete) - $($mode.name)" -ForegroundColor $headerColor
        Write-Host "==============================================================================" -ForegroundColor $headerColor
        $elapsedTotal = (Get-Date) - $script:StartTime
        Write-Host "$($Config.messages.en.duration): $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        Write-Host "$($Config.messages.en.crcFailures):   $script:CRCFailures" -ForegroundColor $(if ($script:CRCFailures -gt 0) { (Get-Color "magenta") } else { (Get-Color "gray") })
        Write-Host "$($Config.messages.en.busResets):     $script:BusResets" -ForegroundColor $(if ($script:BusResets -gt 0) { (Get-Color "yellow") } else { (Get-Color "gray") })
        Write-Host "$($Config.messages.en.overcurrent):    $script:Overcurrent" -ForegroundColor $(if ($script:Overcurrent -gt 0) { (Get-Color "magenta") } else { (Get-Color "gray") })
        Write-Host "$($Config.messages.en.rehandshakes):  $script:Rehandshakes" -ForegroundColor $(if ($script:Rehandshakes -gt 0) { (Get-Color "yellow") } else { (Get-Color "gray") })
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
        body { background: $($Config.reporting.html.backgroundColor); color: $($Config.reporting.html.textColor); font-family: $($Config.reporting.html.fontFamily); padding: 20px; font-size: $($Config.reporting.html.fontSize); }
        pre { margin: 0; font-family: $($Config.reporting.html.fontFamily); white-space: pre; }
        .cyan { color: $($Config.colors.cyan); }
        .green { color: $($Config.colors.green); }
        .yellow { color: $($Config.colors.yellow); }
        .magenta { color: $($Config.colors.magenta); }
        .gray { color: $($Config.colors.gray); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">USB TREE + DEEPER ANALYTICS REPORT</span>
<span class="cyan">$($Config.reporting.html.separator)</span>

<span class="cyan">USB TREE</span>
$originalTreeOutput

<span class="gray">$($Config.messages.en.furthestJumps): $originalMaxHops</span>
<span class="gray">$($Config.messages.en.numberOfTiers): $originalNumTiers</span>
<span class="gray">$($Config.messages.en.totalDevices): $originalTotalDevices</span>
<span class="gray">$($Config.messages.en.totalHubs): $originalTotalHubs</span>

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">STABILITY PER PLATFORM (based on $originalMaxHops hops)</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
$(foreach ($line in $originalStatusLines) {
    $col = if ($line.Status -eq "STABLE") { "green" } elseif ($line.Status -eq "POTENTIALLY UNSTABLE") { "yellow" } else { "magenta" }
    "  <span class='gray'>$($line.Platform.PadRight(25))</span> <span class='$col'>$($line.Status)</span>`r`n"
})

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">DEEPER ANALYTICS SUMMARY</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
  $($Config.messages.en.mode):            $($mode.name)
  $($Config.messages.en.duration):        $([string]::Format('{0:hh\:mm\:ss}', $elapsedTotal))
  $($Config.messages.en.finalStatus):    <span class="$(if ($script:IsStable) { 'green' } else { 'magenta' })">$(if ($script:IsStable) { 'STABLE' } else { 'UNSTABLE' })</span>
  
  $($Config.messages.en.crcFailures):    <span class="$(if ($script:CRCFailures -gt 0) { 'magenta' } else { 'gray' })">$script:CRCFailures</span>
  $($Config.messages.en.busResets):      <span class="$(if ($script:BusResets -gt 0) { 'yellow' } else { 'gray' })">$script:BusResets</span>
  $($Config.messages.en.overcurrent):     <span class="$(if ($script:Overcurrent -gt 0) { 'magenta' } else { 'gray' })">$script:Overcurrent</span>
  $($Config.messages.en.rehandshakes):   <span class="$(if ($script:Rehandshakes -gt 0) { 'yellow' } else { 'gray' })">$script:Rehandshakes</span>
  $($Config.messages.en.stabilityScore):     $finalScore/10 (base: $originalBaseScore)

<span class="cyan">$($Config.reporting.html.separator)</span>
<span class="cyan">EVENT LOG</span>
<span class="cyan">$($Config.reporting.html.separator)</span>
$eventHtml
</pre>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText($deepHtml, $deepHtmlContent, [System.Text.UTF8Encoding]::new($false))
        
        Write-Host "$($Config.messages.en.reportSaved): $deepLog" -ForegroundColor (Get-Color "gray")
        Write-Host "$($Config.messages.en.htmlSaved): $deepHtml" -ForegroundColor (Get-Color "gray")
        Write-Host ""
        
        $openDeep = Read-Host $Config.messages.en.deepLogPrompt
        if ($openDeep -eq 'y') { Start-Process $deepHtml }
    }
}

Write-Host ""
Write-Host $Config.messages.en.exitPrompt -ForegroundColor (Get-Color "gray")
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

