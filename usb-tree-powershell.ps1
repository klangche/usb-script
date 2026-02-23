# usb-tree-powershell.ps1 - USB Tree Diagnostic for Windows

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

# Get devices with better name fallback
$devices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, @{n='Name';e={$_.FriendlyName ?? $_.Name ?? $_.InstanceId}}

$map = @{}
foreach ($d in $devices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ Name = $d.Name; Parent = $parent }
    } catch {}
}

# Recursive print with hops
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

$statusSummary = ""
foreach ($plat in $platforms.Keys) {
    $rec = $platforms[$plat].rec
    $max = $platforms[$plat].max
    $status = if ($numTiers -le $rec) { "Stable" } 
              elseif ($numTiers -le $max) { "Potentially unstable" } 
              else { "Not stable" }
    $color = if ($status -eq "Stable") { "#0f0" } elseif ($status -eq "Potentially unstable") { "#ffa500" } else { "#ff69b4" }
    $statusSummary += "$plat`t`t<span style='color:$color'>$status</span>`n"
}

$hostStatus = if ($numTiers -le 5) { "Stable" } 
              elseif ($numTiers -le 7) { "Potentially unstable" } 
              else { "Not stable" }
$hostColor = if ($hostStatus -eq "Stable") { "#0f0" } elseif ($hostStatus -eq "Potentially unstable") { "#ffa500" } else { "#ff69b4" }

# Terminal output
Write-Host "=== USB Tree (basic) ===" -ForegroundColor Cyan
Write-Host $treeOutput
Write-Host "Furthest jumps: $maxHops"
Write-Host "Number of tiers: $numTiers"
Write-Host "Total devices: $deviceCount"
Write-Host ""
Write-Host "=== Stability per platform (based on $maxHops hops) ===" -ForegroundColor Cyan
Write-Host $statusSummary.Replace("<span style='color:#0f0'>", "").Replace("</span>", "")  # Strip HTML for terminal
Write-Host ""
Write-Host "=== Host summary ===" -ForegroundColor Cyan
Write-Host "Host status: <span style='color:$hostColor'>$hostStatus</span>"
Write-Host "Stability Score: $stabilityScore/10"
Write-Host "If unstable: Reduce number of tiers."
Write-Host ""

# Save txt
"USB Tree Report - $dateStamp`n`n$treeOutput`nFurthest jumps: $maxHops`nNumber of tiers: $numTiers`nTotal devices: $deviceCount`n`nStability Summary`n$statusSummary`nHost Status: $hostStatus (Score: $stabilityScore/10)" | Out-File $outTxt

# HTML with colors
$html = @"
<html><body style='font-family:Consolas,monospace;background:#000;color:#0f0;padding:20px;'>
<h1>USB Tree Report - $dateStamp</h1>
<pre>$treeOutput</pre>
<p>Furthest jumps: $maxHops<br>Number of tiers: $numTiers<br>Total devices: $deviceCount</p>
<h2>Stability Summary</h2>
<pre>$statusSummary</pre>
<h2>Host Status: <span style='color:$hostColor'>$hostStatus</span> (Score: $stabilityScore/10)</h2>
</body></html>
"@
$html | Out-File $outHtml

Write-Host "Report saved as $outTxt"
$open = Read-Host "Open HTML report in browser? (y/n)"
if ($open -match '^[yY]') { Start-Process $outHtml }
