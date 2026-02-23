# usb-tree-powershell.ps1 - USB Tree Diagnostic för Windows

Write-Host "USB Tree Diagnostic Tool - Windows-läge" -ForegroundColor Cyan
Write-Host "Plattform: Windows ($([System.Environment]::OSVersion.VersionString))" -ForegroundColor Cyan
Write-Host ""

$isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Körs med admin: $isElevated" -ForegroundColor Yellow
Write-Host "Notera: Trädet är grundläggande. För full detalj, använd Git Bash eller Linux/macOS." -ForegroundColor DarkYellow
Write-Host ""

$dateStamp = Get-Date -Format yyyyMMdd-HHmm
$outTxt = "$env:TEMP\usb-tree-report-$dateStamp.txt"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"

# Hämta enheter och bygg tree (din kod + liten förbättring)
$devices = Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | Select-Object InstanceId, @{n='Name';e={$_.FriendlyName -or $_.Name}}
$map = @{}
foreach ($d in $devices) {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $d.InstanceId.Replace('\','\\')
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        $parent = $reg.ParentIdPrefix
        $map[$d.InstanceId] = @{ Name = $d.Name; Parent = $parent }
    } catch {}
}

# Rekursiv utskrift med hops
$treeOutput = ""
$maxHops = 0
function Print-Node {
    param($id, $lvl)
    $script:treeOutput += '  ' * $lvl + "- $($map[$id].Name) ($id) ← $lvl hops`n"
    $script:maxHops = [Math]::Max($maxHops, $lvl)
    $kids = $map.Keys | Where-Object { $map[$_].Parent -and $id -like "*$($map[$_].Parent)*" }
    foreach ($c in $kids) { Print-Node $c ($lvl+1) }
}
foreach ($id in $map.Keys) {
    if (-not $map[$id].Parent) { Print-Node $id 0 }
}

# Stabilitetslogik (hårdkodade gränser)
$numTiers = $maxHops + 1
$stabilityScore = [Math]::Max(1, 9 - $maxHops)   # 9 max, sjunker med hops

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
    $statusSummary += "$plat`t`t$status`n"
}

$hostStatus = if ($numTiers -le 5) { "Stable" } 
              elseif ($numTiers -le 7) { "Potentially unstable" } 
              else { "Not stable" }

# Terminal-utskrift med färger
Write-Host "=== USB Tree (grundläggande) ===" -ForegroundColor Cyan
Write-Host $treeOutput
Write-Host "Furthest jumps: $maxHops"
Write-Host "Number of tiers: $numTiers"
Write-Host "Total devices: $($devices.Count)"
Write-Host ""
Write-Host "=== Stability per platform (based on $maxHops hops) ===" -ForegroundColor Cyan
Write-Host $statusSummary
Write-Host ""
Write-Host "=== Host summary ===" -ForegroundColor Cyan
Write-Host "Host status: $hostStatus"
Write-Host "Stability Score: $stabilityScore/10"
Write-Host "If unstable: Reduce number of tiers."
Write-Host ""

# Spara txt
$treeOutput | Out-File $outTxt
$statusSummary | Out-File $outTxt -Append

# Enkel HTML
$html = @"
<html><body>
<h1>USB Tree Report - $dateStamp</h1>
<pre>$treeOutput</pre>
<h2>Stability Summary</h2>
<pre>$statusSummary</pre>
<h2>Host Status: $hostStatus (Score: $stabilityScore/10)</h2>
</body></html>
"@
$html | Out-File $outHtml

Write-Host "Repport saved as $outTxt"
$open = Read-Host "Open Report in Browser? (y/n)"

if ($open -match '^[yY]') { Start-Process $outHtml }
