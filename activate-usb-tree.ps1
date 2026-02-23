# Activate-usb-tree.ps1 - Smart USB Tree Diagnostic Launcher
# Klistra in: irm https://raw.githubusercontent.com/DITT-KONTO/usb-tools/main/Activate-usb-tree.ps1 | iex

Write-Host "USB Tree Diagnostic Tool - Launcher" -ForegroundColor Cyan
Write-Host "Trying to find best diagnostic mode..." -ForegroundColor Yellow
Write-Host ""

# Försök köra bash-version om bash eller sh finns
if (Get-Command bash -ErrorAction SilentlyContinue) {
    Write-Host "Bash hittades → kör full terminal-version (bäst för Linux/macOS)" -ForegroundColor Green
    bash -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-terminal.sh | bash"
    exit
} elseif (Get-Command sh -ErrorAction SilentlyContinue) {
    Write-Host "sh hittades → kör terminal-version" -ForegroundColor Green
    sh -c "curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/main/usb-tree-terminal.sh | bash"
    exit
}

# Annars → native PowerShell (vanlig Windows)
Write-Host "Ingen bash hittades → kör Windows PowerShell-läge" -ForegroundColor Yellow
Write-Host "Notera: Trädet blir grundläggande utan lsusb/system_profiler" -ForegroundColor DarkYellow
Write-Host ""

# Fråga om admin
$adminChoice = Read-Host "do you have admin rights? (y/n)"
if ($adminChoice -match '^[yY]') {
    Write-Host "Begär elevation..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex" -Verb RunAs
    exit
}

# Kör non-admin Windows-version direkt

irm https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-powershell.ps1 | iex
