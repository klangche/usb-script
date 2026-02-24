# =============================================================================
# USB Tree Diagnostic Tool - Windows Launcher
# =============================================================================
# Launches the USB diagnostic on Windows. Checks for bash (e.g., Git Bash) and
# falls back to native PowerShell if not available. Downloads scripts in-memory
# for zero-footprint execution.
#
# Updates: Removed references to removed 'activate' scripts. Uses current repo files.
#
# TODO: Add WSL detection for better cross-compat.
#
# DEBUG TIP: If download fails, check internet or run 'Invoke-RestMethod' manually.
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Windows Launcher" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: Windows $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "Zero-footprint mode: Everything runs in memory" -ForegroundColor Gray
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""

# Check for bash availability.
$hasBash = Get-Command bash -ErrorAction SilentlyContinue

if ($hasBash) {
    Write-Host "Bash detected - using Linux-compatible script for max detail" -ForegroundColor Green
    Write-Host "(Loads in memory via pipe, no files saved)" -ForegroundColor Gray
    Write-Host ""
    
    # Download and run (prefer curl if available).
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh | bash"
    } else {
        $scriptContent = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh"
        $scriptContent | bash
    }
} else {
    Write-Host "No bash detected - running native PowerShell mode" -ForegroundColor Yellow
    Write-Host ""
    
    # Download and execute PowerShell version.
    $psScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
    Invoke-Expression $psScript
}
