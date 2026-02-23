# =============================================================================
# ACTIVATE USB TREE - Windows Launcher
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
    Write-Host "No bash detected - running native PowerShell mode" -ForegroundColor Yellow
    Write-Host ""
    
    # Run PowerShell version directly
    $psScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
    Invoke-Expression $psScript
}
