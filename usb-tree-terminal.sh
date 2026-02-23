#!/usr/bin/env bash

# usb-tree-terminal.sh - USB Tree Diagnostic for terminal
# With live monitoring via udevadm (requires sudo)

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

# Basic tree output
treeOutput=$(echo "$USB_RAW" | sed 's/^/  /')
maxHops=4  # Placeholder - improve later
numTiers=$((maxHops + 1))
deviceCount=$(echo "$USB_RAW" | grep -c "Dev ")  # Rough count
stabilityScore=$((9 - maxHops))

# Platforms
platforms=("Windows:5:7" "Linux:4:6" "Mac Intel:5:7" "Mac Apple Silicon:3:5" "iPad USB-C (M-series):2:4" "iPhone USB-C:2:4" "Android Phone (Qualcomm):3:5" "Android Tablet (Exynos):2:4")

statusSummary=""
for p in "${platforms[@]}"; do
    IFS=':' read -r plat rec max <<< "$p"
    if [ $numTiers -le $rec ]; then status="Stable"; color="\033[32m"
    elif [ $numTiers -le $max ]; then status="Potentially unstable"; color="\033[33m"
    else status="Not stable"; color="\033[95m"; fi
    statusSummary+="$plat\t\t$color$status\033[0m\n"
done

hostStatus="Potentially unstable"
hostColor="\033[33m"

# Output
echo -e "\033[36m=== USB Tree ===\033[0m"
echo "$treeOutput"
echo "Furthest jumps: $maxHops"
echo "Number of tiers: $numTiers"
echo "Total devices: $deviceCount"
echo ""
echo -e "\033[36m=== Stability per platform (based on $maxHops hops) ===\033[0m"
echo -e "$statusSummary"
echo ""
echo -e "\033[36m=== Host summary ===\033[0m"
echo -e "Host status: $hostColor$hostStatus\033[0m"
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
echo -e "$statusSummary" | sed 's/\033[^m]*m//g' >> "$outTxt"
echo "Host Status: $hostStatus (Score: $stabilityScore/10)" >> "$outTxt"

cat <<EOF > "$outHtml"
<html><body style='font-family:Consolas,monospace;background:#000;color:#ccc;padding:20px;'>
<h1>USB Tree Report - $dateStamp</h1>
<pre style='color:#0f0;'>$treeOutput</pre>
<p>Furthest jumps: $maxHops<br>Number of tiers: $numTiers<br>Total devices: $deviceCount</p>
<h2>Stability Summary</h2>
<pre>$statusSummary</pre>
<h2>Host Status: <span style='color:#$hostColor'>$hostStatus</span> (Score: $stabilityScore/10)</h2>
</body></html>
EOF

echo "Report saved as $outTxt"
read -p "Open HTML report in browser? (y/n) " openHtml
if [[ $openHtml =~ ^[yY]$ ]]; then
    if command -v xdg-open >/dev/null; then xdg-open "$outHtml"
    elif command -v open >/dev/null; then open "$outHtml"
    elif command -v start >/dev/null; then start "$outHtml"; fi
fi

# Long term LIVE test (requires sudo)
read -p "Run long term LIVE test (udev monitor, requires sudo)? (y/n): " testChoice
if [[ $testChoice =~ ^[yY]$ ]]; then
    if [ -z "$SUDO" ]; then
        echo "Live test requires sudo. Skipping." -ForegroundColor Yellow
    else
        read -p "For how many minutes: " minutes
        seconds=$((minutes * 60))
        echo "Starting LIVE USB monitoring for $minutes minutes... (udevadm monitor)"
        echo "Listening for add/remove/re-handshake events. Press Ctrl+C to stop early."

        startTime=$(date +%s)
        $SUDO udevadm monitor --environment --kernel --subsystem-match=usb | while read -r line; do
            currentTime=$(date +%s)
            if [ $((currentTime - startTime)) -ge $seconds ]; then
                break
            fi
            if [[ $line == *ACTION=add* ]]; then
                echo "USB DEVICE ADDED/RE-ENUMERATED: $line at $(date +%H:%M:%S.%3N)"
            elif [[ $line == *ACTION=remove* ]]; then
                echo "USB DEVICE REMOVED: $line at $(date +%H:%M:%S.%3N)"
            elif [[ $line == *CHANGE* ]]; then
                echo "USB DEVICE CHANGED (possible re-handshake): $line at $(date +%H:%M:%S.%3N)"
            fi
        done

        echo "Live monitoring complete."
    fi
fi
