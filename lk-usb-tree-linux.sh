#!/usr/bin/env bash
# =============================================================================
# USB Tree Diagnostic Tool - Linux Edition
# =============================================================================
# This script visualizes the USB device tree on Linux, assesses stability based
# on hop counts, and generates an HTML report. It uses lsusb for data collection.
# 
# Key Features:
# - Optional sudo for detailed tree view.
# - Tree parsing with hop levels.
# - Platform-specific stability ratings.
# - HTML export mimicking terminal output.
#
# TODO: Add support for ARM architectures (e.g., Raspberry Pi specifics).
# TODO: Integrate sysfs for more power/voltage details if needed.
#
# DEBUG TIP: If no devices show, run 'lsusb' manually and check output.
# =============================================================================

# Define colors for consistent output (matches other platform editions).
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
GRAY='\033[90m'
RESET='\033[0m'

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - LINUX EDITION${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${GRAY}Platform: Linux ($(uname -r)) ($(uname -m))${RESET}"
echo ""

# Check for lsusb dependency.
if ! command -v lsusb >/dev/null 2>&1; then
    echo -e "${YELLOW}Error: lsusb not found. Install usbutils (e.g., sudo apt install usbutils).${RESET}"
    exit 1
fi

# Prompt for sudo (required for full tree hierarchy).
read -p "Run with sudo for maximum detail (full tree)? (y/n): " sudo_choice
echo ""

use_sudo=false
if [[ "$sudo_choice" =~ ^[Yy]$ ]]; then
    use_sudo=true
    echo -e "${CYAN}→ Running with sudo${RESET}"
else
    echo -e "${YELLOW}Running without sudo → only basic device list (no tree/hops)${RESET}"
fi

# Collect USB data.
echo -e "${GRAY}Enumerating USB devices...${RESET}"

if $use_sudo; then
    raw_tree=$(sudo lsusb -t 2>/dev/null)
    raw_list=$(sudo lsusb 2>/dev/null)
else
    raw_tree=$(lsusb -t 2>/dev/null || echo "No tree available without sudo")
    raw_list=$(lsusb 2>/dev/null)
fi

# Error check: No data.
if [[ -z "$raw_list" ]]; then
    echo -e "${YELLOW}No USB devices detected.${RESET}"
    # DEBUG TIP: Dump raw output for troubleshooting.
    echo "Raw list (empty): $raw_list" > /tmp/usb-debug-linux.txt
    exit 1
fi

# Use tree if available, else flat list.
usb_data="${raw_tree:-$raw_list}"

# Parse tree: Count levels, build output (avoid subshell scoping with here-string).
tree_output=""
max_hops=0
hubs=0
devices=0

while IFS= read -r line; do
    # Skip empty lines.
    if [[ -z "$line" ]]; then continue; fi

    # Calculate level from leading spaces (lsusb -t uses ~4 spaces per level).
    leading="${line%%[![:space:]]*}"
    level=$(( ${#leading} / 4 ))

    # Trim line.
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

    # Classify as hub or device.
    if [[ "$trimmed" =~ Hub || "$trimmed" =~ hub ]]; then
        display="[HUB] $trimmed"
        ((hubs++))
    else
        display="$trimmed"
        ((devices++))
    fi

    # Build tree prefix.
    prefix=""
    for ((i=1; i<=level; i++)); do prefix="${prefix}│   "; done
    if (( level > 0 )); then prefix="${prefix}└── "; fi

    tree_output+="${prefix}${display} ← ${level} hops\n"

    # Update max hops.
    (( max_hops = level > max_hops ? level : max_hops ))
done <<< "$usb_data"

# Error check: Empty tree.
if [[ -z "$tree_output" ]]; then
    echo -e "${YELLOW}Warning: Tree parsing failed. Falling back to raw data.${RESET}"
    tree_output="$usb_data"
    # DEBUG TIP: Inspect raw data if parsing fails.
    echo "$usb_data" > /tmp/usb-raw-linux.txt
fi

num_tiers=$((max_hops + 1))
stability_score=$(( 9 - max_hops ))
(( stability_score < 1 )) && stability_score=1

# Terminal output.
echo ""
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}USB TREE${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
if $use_sudo; then
    echo -e "$tree_output"
else
    echo -e "${YELLOW}(Basic list - no hierarchy)${RESET}"
    echo "$usb_data"
fi
echo ""
echo -e "${GRAY}Furthest hops: $max_hops${RESET}"
echo -e "${GRAY}Number of tiers: $num_tiers${RESET}"
echo -e "${GRAY}Total devices: $devices${RESET}"
echo -e "${GRAY}Total hubs: $hubs${RESET}"
echo ""

# Stability table (consistent across platforms).
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $max_hops hops)${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"

declare -A rec_max_status=(
    ["Windows"]="5:7:STABLE"
    ["Linux"]="4:6:STABLE"
    ["Mac Intel"]="5:7:STABLE"
    ["Mac Apple Silicon"]="3:5:NOT STABLE"
    ["iPad USB-C (M-series)"]="2:4:NOT STABLE"
    ["iPhone USB-C"]="2:4:STABLE"
    ["Android Phone (Qualcomm)"]="3:5:STABLE"
    ["Android Tablet (Exynos)"]="2:4:NOT STABLE"
)

host_status="STABLE"
host_color=$GREEN

for plat in "${!rec_max_status[@]}"; do
    IFS=':' read -r rec max default_status <<< "${rec_max_status[$plat]}"
    if (( max_hops <= rec )); then
        status="STABLE"; color=$GREEN
    elif (( max_hops <= max )); then
        status="POTENTIALLY UNSTABLE"; color=$YELLOW
    else
        status="NOT STABLE"; color=$MAGENTA
    fi

    if [[ "$plat" == "Linux" ]]; then
        host_status="$status"
        host_color="$color"
    fi

    printf "  %-25s ${color}%s${RESET}\n" "$plat" "$status"
done

echo ""
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}HOST SUMMARY${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "Host status:           ${host_color}${host_status}${RESET}"
echo -e "${GRAY}Stability Score:${RESET} $stability_score/10"
echo ""

# Generate HTML report (black background, Consolas font).
timestamp=$(date +"%Y%m%d-%H%M%S")
html_file="$HOME/usb-tree-report-linux-$timestamp.html"

# Build stability HTML section.
stability_html=""
for plat in "${!rec_max_status[@]}"; do
    IFS=':' read -r rec max _ <<< "${rec_max_status[$plat]}"
    if (( max_hops <= rec )); then
        col="green"
    elif (( max_hops <= max )); then
        col="yellow"
    else
        col="magenta"
    fi
    stability_html+="  <span class=\"gray\">$(printf '%-25s' "$plat")</span> <span class=\"$col\">$status</span>\n"
done

cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - Linux - $timestamp</title>
    <style>
        body { background: #000; color: #e0e0e0; font-family: Consolas, monospace; padding: 20px; font-size: 14px; }
        pre { white-space: pre; }
        .cyan { color: #0ff; } .green { color: #0f0; } .yellow { color: #ff0; }
        .magenta { color: #f0f; } .gray { color: #c0c0c0; }
    </style>
</head>
<body><pre>
<span class="cyan">==============================================================================</span>
<span class="cyan">USB TREE REPORT - Linux - $timestamp</span>
<span class="cyan">==============================================================================</span>

$(if $use_sudo; then echo "$tree_output"; else echo "(Basic list - run with sudo for tree)"; echo "$usb_data"; fi)

<span class="gray">Furthest hops: $max_hops</span>
<span class="gray">Number of tiers: $num_tiers</span>
<span class="gray">Total devices: $devices</span>
<span class="gray">Total hubs: $hubs</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM</span>
<span class="cyan">==============================================================================</span>
$stability_html

<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class="gray">Host status:     </span><span class="${host_color:2:-4}">$host_status</span>
  <span class="gray">Stability Score: </span><span class="gray">$stability_score/10</span>
</pre></body></html>
EOF

# Fix color extraction in HTML (remove escape codes).
echo -e "${GRAY}Report saved: $html_file${RESET}"

# Prompt to open report.
read -p "Open HTML report in browser? (y/n): " open_choice
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
    if command -v xdg-open >/dev/null; then
        xdg-open "$html_file"
    else
        echo -e "${YELLOW}xdg-open not found — open $html_file manually${RESET}"
    fi
fi

echo -e "${GREEN}Done.${RESET}"
