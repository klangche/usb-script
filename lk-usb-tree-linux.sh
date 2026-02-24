#!/usr/bin/env bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Linux Edition
# =============================================================================
# Linux-focused version — mirrors PowerShell UX as closely as possible
# Uses lsusb -t for tree (requires sudo for full hierarchy)
# Same prompts, colors, stability logic, HTML style
# =============================================================================

# Colors (match PowerShell)
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

# Check lsusb availability
if ! command -v lsusb >/dev/null 2>&1; then
    echo -e "${YELLOW}Error: lsusb not found. Install usbutils package (apt/yum/dnf/pacman install usbutils)${RESET}"
    exit 1
fi

# =============================================================================
# Sudo prompt (critical on Linux for lsusb -t tree)
# =============================================================================
read -p "Run with sudo for maximum detail (full tree)? (y/n): " sudo_choice
echo ""

use_sudo=false
if [[ "$sudo_choice" =~ ^[Yy]$ ]]; then
    use_sudo=true
    echo -e "${CYAN}→ Running with sudo${RESET}"
else
    echo -e "${YELLOW}Running without sudo → only basic device list (no tree/hops)${RESET}"
fi

# =============================================================================
# Collect data
# =============================================================================
echo -e "${GRAY}Enumerating USB devices...${RESET}"

if $use_sudo; then
    raw_tree=$(sudo lsusb -t 2>/dev/null)
    raw_list=$(sudo lsusb 2>/dev/null)
else
    raw_tree=$(lsusb -t 2>/dev/null || echo "No tree available without sudo")
    raw_list=$(lsusb 2>/dev/null)
fi

if [[ -z "$raw_list" ]]; then
    echo -e "${YELLOW}No USB devices detected.${RESET}"
    exit 1
fi

# Use tree output if available, else fallback to flat list
usb_data="${raw_tree:-$raw_list}"

# Simple hop/level parsing from lsusb -t (preserves its built-in tree symbols)
tree_output=""
max_hops=0
hubs=0
devices=0

echo "$usb_data" | while IFS= read -r line; do
    # Count leading spaces/tabs for level (lsusb -t uses spaces)
    leading="${line%%[![:space:]]*}"

    level=$(( ${#leading} / 4 ))  # usually 4 spaces per level

    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

    if [[ -z "$trimmed" ]]; then continue; fi

    # Count hubs/devices roughly
    if [[ "$trimmed" =~ Hub || "$trimmed" =~ hub ]]; then
        display="[HUB] $trimmed"
        ((hubs++))
    else
        display="$trimmed"
        ((devices++))
    fi

    # Build tree line with hops
    prefix=""
    for ((i=1; i<=level; i++)); do prefix="${prefix}│   "; done
    if (( level > 0 )); then prefix="${prefix}└── "; fi

    tree_output+="${prefix}${display} ← ${level} hops\n"

    (( max_hops = level > max_hops ? level : max_hops ))
done

num_tiers=$((max_hops + 1))
stability_score=$(( 9 - max_hops ))
(( stability_score < 1 )) && stability_score=1

# =============================================================================
# Terminal output (same structure as PowerShell)
# =============================================================================
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

# Stability table (exact same as PowerShell)
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

# =============================================================================
# HTML report (black background, Consolas, colors)
# =============================================================================
timestamp=$(date +"%Y%m%d-%H%M%S")
html_file="$HOME/usb-tree-report-linux-$timestamp.html"

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
$(for p in "${!rec_max_status[@]}"; do IFS=':' read rec max _ <<< "${rec_max_status[$p]}";
  if (( max_hops <= rec )); then col="green"; elif (( max_hops <= max )); then col="yellow"; else col="magenta"; fi;
  echo "  <span class=\"gray\">$(printf '%-25s' "$p")</span> <span class=\"$col\">$status</span>"; done)

<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class="gray">Host status:     </span><span class="${host_color/#\\033\[([0-9;]+)m/}">$host_status</span>
  <span class="gray">Stability Score: </span><span class="gray">$stability_score/10</span>
</pre></body></html>
EOF

echo -e "${GRAY}Report saved: $html_file${RESET}"

read -p "Open HTML report in browser? (y/n): " open_choice
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
    if command -v xdg-open >/dev/null; then
        xdg-open "$html_file"
    else
        echo -e "${YELLOW}xdg-open not found — open $html_file manually${RESET}"
    fi
fi

echo -e "${GREEN}Done.${RESET}"
