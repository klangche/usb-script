# usb-tree-powershell.ps1 - USB Tree Diagnostic for Windows
# Compatible with PowerShell 5.1 and 7+ – Host status strict (Stable only if all platforms Stable)

Write-Host "USB Tree Diagnostic Tool - Windows mode" -ForegroundColor Cyan
Write-Host "Platform: Windows ($([System.Environment]::OSVersion.VersionString))" -ForegroundColor Cyan
Write-Host ""

$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Running with admin: $isElevated" -ForegroundColor Yellow
Write-Host "Note: Tree is basic without lsusb/system_profiler. For full detail, use Git Bash or Linux/macOS." -ForegroundColor DarkYellow
Write-Host ""

$dateStamp = Get-Date -Format yyyyMMdd-HHmm
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

# Get devices with PS 5.1 compatible name fallback
$devices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, @{n='Name';e={
    if ($_.FriendlyName) { $_.FriendlyName }
    elseif ($_.Name) { $_.Name }
    else { $_.InstanceId }
}}

$map = @{}
foreach ($d in $devices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ Name = $d.Name; Parent = $parent }
    } catch {}
}

# Recursive print
$treeOutput = ""
$maxHops = 0
$deviceCount = $devices.Count
function Print-Node {
    param($id, $lvl)
    $node = $map[$id]
    if ($node) {
        $script:treeOutput += '  ' * $lvl + "- $($node.Name) ($id) ← $lvl hops`n"
        $script:maxHops = [Math]::Max($script:maxHops, $lvl)
    }
    $kids = $map.Keys | Where-Object { $map[$_].Parent -and $id -like "*$($map[$_].Parent)*" }
    foreach ($c in $kids) { Print-Node $c ($lvl+1) }
}
foreach ($id in $map.Keys) {
    if (-not $map[$id].Parent) { Print-Node $id 0 }
}

$numTiers = $maxHops + 1
$stabilityScore = [Math]::Max(1, 9 - $maxHops)

# Platforms and limits
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

# Build aligned status list
$statusLines = @()
foreach ($plat in $platforms.Keys) {
    $rec = $platforms[$plat].rec
    $max = $platforms[$plat].max
    $status = if ($numTiers -le $rec) { "Stable" } 
              elseif ($numTiers -le $max) { "Potentially unstable" } 
              else { "Not stable" }
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

$statusSummaryHtml = ""
foreach ($line in $statusLines) {
    $color = if ($line.Status -eq "Stable") { "#0f0" } 
             elseif ($line.Status -eq "Potentially unstable") { "#ffa500" } 
             else { "#ff69b4" }
    $statusSummaryHtml += "$($line.Platform)`t`t<span style='color:$color'>$($line.Status)</span>`n"
}

# Strict host status: Stable ONLY if ALL platforms are Stable
$hostStatus = "Stable"
$hostColor = "#0f0"

foreach ($line in $statusLines) {
    if ($line.Status -eq "Potentially unstable" -and $hostStatus -eq "Stable") {
        $hostStatus = "Potentially unstable"
        $hostColor = "#ffa500"
    }
    if ($line.Status -eq "Not stable") {
        $hostStatus = "Not stable"
        $hostColor = "#ff69b4"
        break
    }
}

# Terminal output
Write-Host "=== USB Tree (basic) ===" -ForegroundColor Cyan
Write-Host $treeOutput
Write-Host "Furthest jumps: $maxHops"
Write-Host "Number of tiers: $numTiers"
Write-Host "Total devices: $deviceCount"
Write-Host ""
Write-Host "=== Stability per platform (based on $maxHops hops) ===" -ForegroundColor Cyan
Write-Host $statusSummaryTerminal
Write-Host ""
Write-Host "=== Host summary ===" -ForegroundColor Cyan
Write-Host "Host status: $hostStatus"
Write-Host "Stability Score: $stabilityScore/10"
Write-Host "If unstable: Reduce number of tiers."
Write-Host ""

# Save txt (plain text)
"USB Tree Report - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $deviceCount`n`nStability Summary`n$statusSummaryTerminal`nHost Status: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt

# HTML with dark theme
$html = @"
<html><body style='font-family:Consolas,monospace;background:#000;color:#ccc;padding:20px;'>
<h1>USB Tree Report - $dateStamp</h1>
<pre style='color:#0f0;'>$treeOutput</pre>
<p>Furthest jumps: $maxHops<br>Number of tiers: $numTiers<br>Total devices: $deviceCount</p>
<h2>Stability Summary</h2>
<pre>$statusSummaryHtml</pre>
<h2>Host Status: <span style='color:$hostColor'>$hostStatus</span> (Score: $stabilityScore/10)</h2>
</body></html>
"@
$html | Out-File $outHtml

Write-Host "Report saved as $outTxt"
$open = Read-Host "Open HTML report in browser? (y/n)"
if ($open -match '^[yY]') { Start-Process $outHtml }
