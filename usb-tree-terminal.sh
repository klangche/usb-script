#!/usr/bin/env bash

# usb-tree-terminal.sh - USB Tree Diagnostic för terminal (Linux/macOS + bash på Windows)

echo "USB Tree Diagnostic Tool - Terminal-läge"
echo "Plattform: $(uname -s) $(uname -m)"
echo ""

read -p "Kör med sudo för bättre detaljer? (y/n) " adminChoice
if [[ $adminChoice =~ ^[yY]$ ]]; then
    sudo -v
    SUDO="sudo "
else
    SUDO=""
fi

OS=$(uname -s)
if [[ $OS == "Darwin" ]]; then
    OS="macOS"
    [[ $(uname -m) == "arm64" ]] && MAC_TYPE="Apple Silicon" || MAC_TYPE="Intel"
    USB_RAW=$(system_profiler SPUSBDataType)
else
    OS="Linux"
    USB_RAW=$($SUDO lsusb -t 2>/dev/null || echo "lsusb saknas")
fi

# Enkel tree-parsning (utöka vid behov)
treeOutput=$(echo "$USB_RAW" | sed 's/^/  /')   # Grundläggande indent
maxHops=3   # Ersätt med riktig parsning (awk/grep för indent-nivå)

numTiers=$((maxHops + 1))
stabilityScore=$((9 - maxHops))
hostStatus="Stable"  # Lägg till logik

platforms=("Windows:5:7" "Linux:4:6" "Mac Intel:5:7" "Mac Apple Silicon:3:5" "iPad USB-C (M-series):2:4" "iPhone USB-C:2:4" "Android Phone (Qualcomm):3:5" "Android Tablet (Exynos):2:4")

statusSummary=""
for p in "${platforms[@]}"; do
    IFS=':' read -r plat rec max <<< "$p"
    if [ $numTiers -le $rec ]; then status="Stable"
    elif [ $numTiers -le $max ]; then status="Potentially unstable"
    else status="Not stable"; fi
    statusSummary+="$plat: $status\n"
done

# Färgad utskrift
echo -e "\033[36m=== USB Tree ===\033[0m"
echo "$treeOutput"
echo "Furthest jumps: $maxHops"
echo "Number of tiers: $numTiers"
echo ""
echo -e "\033[36m=== Stability per platform (based on $maxHops hops) ===\033[0m"
echo -e "$statusSummary"
echo ""
echo -e "\033[36m=== Host summary ===\033[0m"
echo "Host status: $hostStatus"
echo "Stability Score: $stabilityScore/10"
echo "If unstable: Reduce number of tiers."
echo ""

dateStamp=$(date +%Y%m%d-%H%M)
outTxt=~/usb-tree-report-$dateStamp.txt
outHtml=~/usb-tree-report-$dateStamp.html

echo "$treeOutput" > "$outTxt"
echo "$statusSummary" >> "$outTxt"

cat <<EOF > "$outHtml"
<html><body>
<h1>USB Tree Report - $dateStamp</h1>
<pre>$treeOutput</pre>
<h2>Stability Summary</h2>
<pre>$statusSummary</pre>
<h2>Host Status: $hostStatus (Score: $stabilityScore/10)</h2>
</body></html>
EOF

echo "Rapport sparad som $outTxt"
read -p "Öppna HTML-rapport i webbläsare? (y/n) " openHtml
if [[ $openHtml =~ ^[yY]$ ]]; then
    if command -v xdg-open >/dev/null; then xdg-open "$outHtml"
    elif command -v open >/dev/null; then open "$outHtml"
    elif command -v start >/dev/null; then start "$outHtml"; fi
fi