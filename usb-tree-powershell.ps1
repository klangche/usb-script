# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Windows PowerShell Edition
# =============================================================================
# - Runs tree visualization + HTML report
# - After that, prompts for deep analytics (y/n)
# - No admin → basic/old polling mode (re-handshakes only)
# - Admin → deeper/new ETW mode (CRC, resets, overcurrent, re-handshakes + more)
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Admin check + smart handling (prompt if not elevated for full detail)
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
# USB enumeration and tree building (your existing code — truncated for brevity)
# ─────────────────────────────────────────────────────────────────────────────
# ... (paste your full enumeration, treeOutput, stability, HTML generation code here) ...

# Example placeholder (replace with your full tree code)
$dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outHtml = "$env:TEMP\usb-tree-report-$dateStamp.html"
# ... build treeOutput, numTiers, stabilityScore, etc. ...
# ... output tree to console ...
# ... save HTML ...

Write-Host "HTML report saved as: $outHtml" -ForegroundColor Gray

# Prompt to open HTML (your existing code)
$openChoice = Read-Host "Open HTML report in browser? (y/n)"
if ($openChoice -match '^[Yy]') {
    Start-Process $outHtml
}

# ─────────────────────────────────────────────────────────────────────────────
# Prompt for deep analytics AFTER tree + HTML
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
# Run deep mode based on admin status
# ─────────────────────────────────────────────────────────────────────────────
if (-not $isAdmin) {
    Write-Host "Starting BASIC deep analytics (re-handshakes / disconnects)..." -ForegroundColor Green
    # Old polling mode (paste your full old polling function here)
    # Example:
    $startTime = Get-Date
    $isStable = $true
    $rehandshakes = 0
    # ... polling loop with Get-PnpDevice comparison ...
    # ... log events to file ...
    # ... display live status ...
    # ... finally block with summary ...
} else {
    Write-Host "Starting DEEPER analytics (CRC, resets, overcurrent, re-handshakes + more)..." -ForegroundColor Green
    # New ETW mode (paste the full ETW function here from previous messages)
    # Example:
    $trace = "LK_USB_TRACE"
    # ... logman start ...
    # ... Get-WinEvent -Wait ...
    # ... pattern matching for counters ...
    # ... finally stop trace and show summary with colors/warnings ...
}

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
