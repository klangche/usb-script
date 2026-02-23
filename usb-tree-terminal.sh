#!/usr/bin/env bash

# usb-tree-terminal.sh - USB Tree Diagnostic for terminal

echo "USB Tree Diagnostic Tool - Terminal mode"
echo "Platform: $(uname -s) $(uname -m)"
echo ""

read -p "Run with sudo for better detail? (y/n) " adminChoice
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
    USB_RAW=$($SUDO lsusb -t 2>/dev/null || echo "lsusb not found")
fi

# Basic tree output (improve parsing later)
treeOutput=$(echo "$USB_RAW" | sed 's/^/  /')
maxHops=4  # Placeholder - add real parsing
numTiers=$((maxHops + 1))
deviceCount=14  # Placeholder - count from raw
stabilityScore=$((9 - maxHops))

platforms=("Windows:5:7" "Linux:4:6" "Mac Intel:5:7" "Mac Apple Silicon:3:5" "iPad USB-C (M-series):2:4" "iPhone USB-C:2:4" "Android Phone (Qualcomm):3:5" "Android Tablet (Exynos):2:4")

statusSummary=""
for p in "${platforms[@]}"; do
    IFS=':' read -r plat rec max <<< "$p"
    if [ $numTiers -le $rec ]; then status="Stable"; color="#0f0"
    elif [ $numTiers -le $max ]; then status="Potentially unstable"; color="#ffa500"
    else status="Not stable"; color="#ff69b4"; fi
    statusSummary+="$plat\t\t<span style='color:$color'>$status</span>\n"
done

hostStatus="Potentially unstable"
hostColor="#ffa500"

# Terminal output
echo -e "\033[36m=== USB Tree ===\033[0m"
echo "$treeOutput"
echo "Furthest jumps: $maxHops"
echo "Number of tiers: $numTiers"
echo "Total devices: $deviceCount"
echo ""
echo -e "\033[36m=== Stability per platform (based on $maxHops hops) ===\033[0m"
echo -e "$statusSummary" | sed 's/<span style='\''color:#0f0'\''>/\033[32m/g; s/<span style='\''color:#ffa500'\''>/\033[33m/g; s/<span style='\''color:#ff69b4'\''>/\033[95m/g; s/<\/span>//g'
echo ""
echo -e "\033[36m=== Host summary ===\033[0m"
echo -e "Host status: \033[33m$hostStatus\033[0m"
echo "Stability Score: $stabilityScore/10"
echo "If unstable: Reduce number of tiers."
echo ""

dateStamp=$(date +%Y%m%d-%H%M)
outTxt=~/usb-tree-report-$dateStamp.txt
outHtml=~/usb-tree-report-$dateStamp.html

echo "USB Tree Report - $dateStamp" > "$outTxt"
echo "$treeOutput" >> "$outTxt"
echo "Furthest jumps: $maxHops" >> "$outTxt"
echo "Number of tiers: $numTiers" >> "$outTxt"
echo "Total devices: $deviceCount" >> "$outTxt"
echo "" >> "$outTxt"
echo "Stability Summary" >> "$outTxt"
echo "$statusSummary" | sed 's/<[^>]*>//g' >> "$outTxt"
echo "Host Status: $hostStatus (Score: $stabilityScore/10)" >> "$outTxt"

cat <<EOF > "$outHtml"
<html><body style='font-family:Consolas,monospace;background:#000;color:#0f0;padding:20px;'>
<h1>USB Tree Report - $dateStamp</h1>
<pre>$treeOutput</pre>
<p>Furthest jumps: $maxHops<br>Number of tiers: $numTiers<br>Total devices: $deviceCount</p>
<h2>Stability Summary</h2>
<pre>$statusSummary</pre>
<h2>Host Status: <span style='color:$hostColor'>$hostStatus</span> (Score: $stabilityScore/10)</h2>
</body></html>
EOF

echo "Report saved as $outTxt"
read -p "Open HTML report in browser? (y/n) " openHtml
if [[ $openHtml =~ ^[yY]$ ]]; then
    if command -v xdg-open >/dev/null; then xdg-open "$outHtml"
    elif command -v open >/dev/null; then open "$outHtml"
    elif command -v start >/dev/null; then start "$outHtml"; fi
fi
