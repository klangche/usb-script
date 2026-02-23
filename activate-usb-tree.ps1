# =============================================================================
# ACTIVATE USB TREE - Windows Launcher with Deep Analytics
# =============================================================================
# This script launches the USB diagnostic tool on Windows
# It automatically detects if bash is available and chooses the best method
#
# Zero-footprint: Everything runs in memory
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Windows Launcher" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "Zero-footprint mode: Everything runs in memory" -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check if bash is available (Git Bash, WSL, etc.)
$hasBash = Get-Command bash -ErrorAction SilentlyContinue

if ($hasBash) {
    Write-Host "Bash detected - using universal script for maximum detail" -ForegroundColor Green
    Write-Host "(Script loads directly in memory via pipe, nothing saved)" -ForegroundColor Gray
    Write-Host ""
    
    # Use curl if available, otherwise PowerShell download
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-terminal.sh | bash"
    } else {
        $scriptContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-terminal.sh"
        $scriptContent | bash
    }
}
else {
    Write-Host "No bash detected - running native PowerShell mode (basic USB tree)" -ForegroundColor Yellow
    Write-Host "For full detail, install Git Bash and run the same command again" -ForegroundColor Yellow
    Write-Host ""
    
    # Menu for PowerShell mode
    Write-Host "Choose mode:" -ForegroundColor Cyan
    Write-Host "  1. Basic USB Tree (quick diagnostic)" -ForegroundColor Gray
    Write-Host "  2. Deep Analytics (real-time monitoring, press Ctrl+C to stop)" -ForegroundColor Magenta
    Write-Host ""
    $mode = Read-Host "Select mode (1 or 2)"
    
    if ($mode -eq "2") {
        # Run Deep Analytics
        Write-Host ""
        Write-Host "Starting Deep Analytics..." -ForegroundColor Magenta
        Write-Host "This will monitor USB stability in real-time until you press Ctrl+C" -ForegroundColor Yellow
        Write-Host ""
        
        # Ask if user wants HTML view
        $htmlChoice = Read-Host "Open HTML monitor in browser? (y/n) - This gives you a separate tab"
        $htmlParam = if ($htmlChoice -match '^[yY]') { "-HtmlOutput" } else { "" }
        
        # Download and run Deep Analytics
        $daScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-deep-analytics.ps1"
        
        # Create a temporary script block with parameter
        $scriptBlock = [scriptblock]::Create($daScript)
        if ($htmlParam) {
            & $scriptBlock -HtmlOutput
        } else {
            & $scriptBlock
        }
    }
    else {
        # Run standard PowerShell version
        $psScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
        Invoke-Expression $psScript
        
        # After HTML report, offer Deep Analytics
        Write-Host ""
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "DEEP ANALYTICS AVAILABLE" -ForegroundColor Magenta
        Write-Host "==============================================================================" -ForegroundColor Cyan
        Write-Host "Would you like to run Deep Analytics to monitor USB stability in real-time?" -ForegroundColor Yellow
        Write-Host "This will track every USB re-handshake and error until you press Ctrl+C" -ForegroundColor Gray
        Write-Host ""
        
        $deepChoice = Read-Host "Run Deep Analytics? (y/n)"
        if ($deepChoice -match '^[yY]') {
            $htmlChoice = Read-Host "Open HTML monitor in browser? (y/n) - This gives you a separate tab"
            $htmlParam = if ($htmlChoice -match '^[yY]') { "-HtmlOutput" } else { "" }
            
            $daScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-deep-analytics.ps1"
            $scriptBlock = [scriptblock]::Create($daScript)
            if ($htmlParam) {
                & $scriptBlock -HtmlOutput
            } else {
                & $scriptBlock
            }
        }
    }
}
