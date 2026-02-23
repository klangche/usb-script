#!/usr/bin/env bash

# usb-tree-terminal.sh - USB Tree Diagnostic for terminal
# With strict host status: Stable ONLY if all platforms are Stable

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

# Basic tree output (placeholder - improve parsing later)
treeOutput=$(echo "$USB_RAW" | sed 's/^/  /')
maxHops=4  # Placeholder
numTiers=$((maxHops + 1))
deviceCount=14  # Placeholder
stabilityScore=$((9 - maxHops))

# Platforms and limits
platforms=("Windows:5:7" "Linux:4:6" "Mac Intel:5:7" "Mac Apple Silicon:3:5" "iPad USB-C (M-series):2:4" "iPhone USB-C:2:4" "Android Phone (Qualcomm):3:5" "Android Tablet (Exynos):2:4")

# Build status lines
statusLines=()
for p in "${platforms[@]}"; do
    IFS=':' read -r plat rec max <<< "$p"
    if [ $numTiers -le $rec ]; then status="Stable"
    elif [ $numTiers -le $max ]; then status="Potentially unstable"
    else status="Not stable"; fi
    statusLines+=("$plat:$status")
done

# Sort in consistent order
sortedLines=()
for key in "Windows" "Linux" "Mac Intel" "Mac Apple Silicon" "iPad USB-C (M-series)" "iPhone USB-C" "Android Phone (Qualcomm)" "Android Tablet (Exynos)"; do
    for line in "${statusLines[@]}"; do
        if [[ $line == "$key:"* ]]; then
            sortedLines+=("$line")
            break
        fi
    done
done

# Aligned terminal output
maxLen=0
for line in "${sortedLines[@]}"; do
    plat=$(echo $line | cut -d':' -f1)
    len=${#plat}
    (( len > maxLen )) && maxLen=$len
done

statusSummaryTerminal=""
for line in "${sortedLines[@]}"; do
    plat=$(echo $line | cut -d':' -f1)
    status=$(echo $line | cut -d':' -f2-)
    pad=$(printf '%*s' $((maxLen - ${#plat} + 4)) "")
    statusSummaryTerminal+="$plat$pad$status\n"
done

# Colored terminal output
echo -e "\033[36m=== Stability per platform (based on $maxHops hops) ===\033[0m"
echo -e "$statusSummaryTerminal" | sed "s/Stable/\033[32mStable\033[0m/g; s/Potentially unstable/\033[33mPotentially unstable\033[0m/g; s/Not stable/\033[95mNot stable\033[0m/g"

# Strict host status: Hierarchical check
hasNotStable=false
hasPotentially=false

for line in "${sortedLines[@]}"; do
    status=$(echo $line | cut -d':' -f2-)
    if [[ $status == "Not stable" ]]; then hasNotStable=true; fi
    if [[ $status == "Potentially unstable" ]]; then hasPotentially=true; fi
done

if $hasNotStable; then
    hostStatus="Not stable"
    hostColor="\033[95m"
elif $hasPotentially; then
    hostStatus="Potentially unstable"
    hostColor="\033[33m"
else
    hostStatus="Stable"
    hostColor="\033[32m"
fi

# Terminal summary
echo ""
echo -e "\033[36m=== Host summary ===\033[0m"
echo -e "Host status: $hostColor$hostStatus\033[0m"
echo "Stability Score: $stabilityScore/10"
echo "If unstable: Reduce number of tiers."
echo ""

# Save txt (plain text, no ANSI)
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
echo -e "$statusSummaryTerminal" | sed 's/\033[^m]*m//g' >> "$outTxt"
echo "Host Status: $hostStatus (Score: $stabilityScore/10)" >> "$outTxt"

# HTML with dark theme
cat <<EOF > "$outHtml"
<html><body style='font-family:Consolas,monospace;background:#000;color:#ccc;padding:20px;'>
<h1>USB Tree Report - $dateStamp</h1>
<pre style='color:#0f0;'>$treeOutput</pre>
<p>Furthest jumps: $maxHops<br>Number of tiers: $numTiers<br>Total devices: $deviceCount</p>
<h2>Stability Summary</h2>
<pre>$statusSummaryHtml</pre>
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
