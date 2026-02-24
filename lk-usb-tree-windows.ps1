# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Universal Launcher
# =============================================================================
# Detects OS and runs appropriate version:
# - Windows: Full PowerShell version with deep analytics
# - Linux/macOS with bash: Downloads and runs bash version
# - Others: Basic mode
#
# Usage: irm https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-windows.ps1 | iex
# =============================================================================

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "USB TREE DIAGNOSTIC TOOL - Universal Launcher" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Platform: $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Gray
Write-Host "Detecting operating system..." -ForegroundColor Gray
Write-Host ""

# Detect OS
$isWindows = $env:OS -match "Windows"
$hasBash = Get-Command bash -ErrorAction SilentlyContinue
$isLinux = $isWindows -eq $false -and (Test-Path "/proc")  # Simple Linux detection
$isMac = $isWindows -eq $false -and (Test-Path "/System/Library/CoreServices")  # Simple macOS detection

if ($isWindows) {
    Write-Host "✓ Windows detected - using PowerShell version" -ForegroundColor Green
    Write-Host ""
    Write-Host "Downloading main Windows script..." -ForegroundColor Gray
    
    try {
        $mainScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1"
        Invoke-Expression $mainScript
    } catch {
        Write-Host "Failed to download Windows script: $_" -ForegroundColor Red
        Write-Host "Please check your internet connection and try again." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
    }
}
elseif ($isLinux -and $hasBash) {
    Write-Host "✓ Linux detected - using bash version" -ForegroundColor Green
    Write-Host ""
    Write-Host "Downloading and running Linux script..." -ForegroundColor Gray
    
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh | bash"
    } else {
        $bashScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh"
        $bashScript | bash
    }
}
elseif ($isMac -and $hasBash) {
    Write-Host "✓ macOS detected - using macOS version" -ForegroundColor Green
    Write-Host ""
    Write-Host "Downloading and running macOS script..." -ForegroundColor Gray
    
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-macos.sh | bash"
    } else {
        $bashScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-macos.sh"
        $bashScript | bash
    }
}
elseif ($hasBash) {
    Write-Host "✓ Unix-like system detected - trying Linux script" -ForegroundColor Yellow
    Write-Host ""
    
    if (Get-Command curl -ErrorAction SilentlyContinue) {
        bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh | bash"
    } else {
        $bashScript = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-linux.sh"
        $bashScript | bash
    }
}
else {
    Write-Host "⚠ Unknown platform - running basic mode" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Basic USB device information:" -ForegroundColor Cyan
    
    try {
        Get-PnpDevice -Class USB | Where-Object {$_.Status -eq 'OK'} | 
        Select-Object FriendlyName, Class, Status | 
        Format-Table -AutoSize
    } catch {
        Write-Host "Unable to enumerate USB devices." -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "For full features, please run on Windows with PowerShell or" -ForegroundColor Gray
    Write-Host "Linux/macOS with bash installed." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
