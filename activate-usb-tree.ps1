# activate-usb-tree.ps1 - Smart USB Tree Diagnostic Launcher
# Works on PowerShell 5.1 and 7+

Write-Host "USB Tree Diagnostic Tool - Launcher" -ForegroundColor Cyan
Write-Host "Detecting PowerShell version..." -ForegroundColor Yellow

$psMajor = $PSVersionTable.PSVersion.Major
Write-Host "PowerShell version detected: $psMajor" -ForegroundColor Cyan

if ($psMajor -lt 7) {
    Write-Host "Warning: Running in Windows PowerShell 5.1 (limited features)" -ForegroundColor Yellow
    Write-Host "For best experience, install PowerShell 7: https://aka.ms/powershell-release" -ForegroundColor Yellow
} else {
    Write-Host "PowerShell 7+ detected – full features available" -ForegroundColor Green
}

# Optional: Suggest relaunch in pwsh if installed
if ((Get-Command pwsh -ErrorAction SilentlyContinue) -and $psMajor -lt 7) {
    $choice = Read-Host "PowerShell 7 is installed. Relaunch in pwsh for better compatibility? (y/n)"
    if ($choice -match '^[yY]') {
        Write-Host "Relaunching in PowerShell 7..." -ForegroundColor Green
        pwsh -NoProfile -Command "irm https://raw.githubusercontent.com/klangche/usb-script/main/activate-usb-tree.ps1 | iex"
        exit
    }
}

Write-Host "Trying to find best diagnostic mode..." -ForegroundColor Yellow
Write-Host ""

# Try bash/sh if available (Linux/macOS/Git Bash/WSL)
if (Get-Command bash -ErrorAction SilentlyContinue) {
    Write-Host "Bash found → running full terminal version" -ForegroundColor Green
    bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-terminal.sh | bash"
    exit
} elseif (Get-Command sh -ErrorAction SilentlyContinue) {
    Write-Host "sh found → running terminal version" -ForegroundColor Green
    sh -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-terminal.sh | bash"
    exit
}

# Fallback to native PowerShell (Windows)
Write-Host "No bash found → running native Windows PowerShell mode" -ForegroundColor Yellow
Write-Host "Note: Tree will be basic without lsusb/system_profiler" -ForegroundColor DarkYellow
Write-Host ""

# Ask for admin
$adminChoice = Read-Host "Do you have admin rights for better detail? (y/n)"
if ($adminChoice -match '^[yY]') {
    Write-Host "Requesting elevation..." -ForegroundColor Yellow
    # Try elevation - if it fails or user cancels, fall back to non-admin
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex" -Verb RunAs -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Elevation failed or cancelled. Running without admin." -ForegroundColor Yellow
    } else {
        exit
    }
}

# Run non-admin directly
irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex
