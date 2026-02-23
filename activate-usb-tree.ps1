# activate-usb-tree.ps1 - Smart USB Tree Diagnostic Launcher

Write-Host "USB Tree Diagnostic Tool - Launcher" -ForegroundColor Cyan
Write-Host "Trying to find best diagnostic mode..." -ForegroundColor Yellow
Write-Host ""

# Try bash if available (Linux/macOS/Git Bash/WSL)
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
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex" -Verb RunAs
    exit
}

# Run non-admin directly
irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex
