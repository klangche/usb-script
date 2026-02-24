#!/usr/bin/env bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition
# =============================================================================
# Mirrors Windows PowerShell version as closely as possible
# Uses system_profiler → parsed tree + hop counts
# Same prompts, colors, stability logic, HTML style
# =============================================================================

# Colors (exact match to PowerShell)
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
GRAY='\033[90m'
RESET='\033[0m'

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - macOS EDITION${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${GRAY}Platform: macOS ($(sw_vers -productVersion 2>/dev/null || echo "Unknown")) ($(uname -m))${RESET}"
echo ""

# =============================================================================
# Admin/sudo prompt (macOS usually doesn't need it for system_profiler)
# =============================================================================
read -p "Run with sudo for maximum detail? (y/n): " sudo_choice
echo ""

use_sudo=false
if [[ "$sudo_choice" =~ ^[Yy]$ ]]; then
    use_sudo=true
    echo -e "${CYAN}→ Running with sudo${RESET}"
else
    echo -e "${YELLOW}Running without sudo (usually sufficient on macOS)${RESET}"
fi

# =============================================================================
# Collect raw data
# =============================================================================
echo -e "${GRAY}Enumerating USB devices...${RESET}"

if $use_sudo; then
    raw_data=$(sudo system_profiler SPUSBDataType 2>/dev/null)
else
    raw_data=$(system_profiler SPUSBDataType 2>/dev/null)
fi

if [[ -z "$raw_data" ]]; then
    echo -e "${YELLOW}No USB data retrieved. Check system_profiler.${RESET}"
    exit 1
fi

# =============================================================================
# Simple tree parsing from indented system_profiler output
# (Improves on repo's basic grep version)
# =============================================================================
tree_output=""
max_hops=0
current_level=0
prev_level=0
hubs=0
devices=0

echo "$raw_data" | while IFS= read -r line; do
    # Count leading spaces to determine level (system_profiler uses 4 spaces per indent)
    leading_spaces="${line%%[^[:space:]]*}"

    level=$(( ${#leading_spaces} / 4 ))

    # Trim line
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

    if [[ -z "$trimmed" || "$trimmed" =~ ^(Product ID:|Vendor ID:|Serial Number:|Speed:|Manufacturer:|Location ID:|Current Available \(mA\):) ]]; then
        continue  # skip metadata lines we don't need for tree
    fi

    if [[ "$trimmed" =~ :$ ]]; then
        name="${trimmed%:}"  # remove trailing :
        name=$(echo "$name" | sed 's/^[[:space:]]*//')

        if [[ "$name" == *Hub* || "$name" == *hub* ]]; then
            display="[HUB] $name"
            ((hubs++))
        else
            display="$name"
            ((devices++))
        fi

        # Tree prefix
        prefix=""
        for ((i=1; i<level; i++)); do
            prefix="${prefix}│   "
        done
        if (( level > 0 )); then
            prefix="${prefix}├── "
        fi

        tree_output+="${prefix}${display} ← ${level} hops\n"
        (( max_hops = level > max_hops ? level : max_hops ))

        current_level=$level
    fi
done

num_tiers=$((max_hops + 1))
stability_score=$(( 9 - max_hops ))
(( stability_score < 1 )) && stability_score=1

# =============================================================================
# Stability assessment (exact same logic/table as PowerShell)
# =============================================================================
echo ""
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}USB TREE${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "$tree_output"
echo ""
echo -e "${GRAY}Furthest hops: $max_hops${RESET}"
echo -e "${GRAY}Number of tiers: $num_tiers${RESET}"
echo -e "${GRAY}Total devices: $devices${RESET}"
echo -e "${GRAY}Total hubs: $hubs${RESET}"
echo ""

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $max_hops hops)${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"

platforms=(
    "Windows:5:7:STABLE"
    "Linux:4:6:STABLE"
    "Mac Intel:5:7:STABLE"
    "Mac Apple Silicon:3:5:NOT STABLE"  # will be overridden
    "iPad USB-C (M-series):2:4:NOT STABLE"
    "iPhone USB-C:2:4:STABLE"
    "Android Phone (Qualcomm):3:5:STABLE"
    "Android Tablet (Exynos):2:4:NOT STABLE"
)

for entry in "${platforms[@]}"; do
    IFS=':' read -r plat rec max _ <<< "$entry"

    if (( max_hops <= rec )); then
        status="STABLE"
        color=$GREEN
    elif (( max_hops <= max )); then
        status="POTENTIALLY UNSTABLE"
        color=$YELLOW
    else
        status="NOT STABLE"
        color=$MAGENTA
    fi

    # Special override for host relevance
    if [[ "$plat" == "Mac Apple Silicon" ]]; then
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
# HTML report (black bg, same style)
# =============================================================================
timestamp=$(date +"%Y%m%d-%H%M%S")
html_file="$HOME/usb-tree-report-$timestamp.html"

cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - $timestamp</title>
    <style>
        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', 'Courier New', monospace; padding: 20px; font-size: 14px; }
        pre { margin: 0; white-space: pre; }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .gray { color: #c0c0c0; }
    </style>
</head>
<body>
<pre>
<span class="cyan">==============================================================================</span>
<span class="cyan">USB TREE REPORT - macOS - $timestamp</span>
<span class="cyan">==============================================================================</span>

$tree_output

<span class="gray">Furthest hops: $max_hops</span>
<span class="gray">Number of tiers: $num_tiers</span>
<span class="gray">Total devices: $devices</span>
<span class="gray">Total hubs: $hubs</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $max_hops hops)</span>
<span class="cyan">==============================================================================</span>
$(for p in "${platforms[@]}"; do IFS=':' read plat rec max _ <<< "$p"; 
  if (( max_hops <= rec )); then col="green"; elif (( max_hops <= max )); then col="yellow"; else col="magenta"; fi;
  echo "  <span class=\"gray\">$(printf '%-25s' "$plat")</span> <span class=\"$col\">$status</span>"; done)

<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class="gray">Host status:           </span><span class="${host_color/#\\033\[([0-9;]+)m/}"> $host_status</span>
  <span class="gray">Stability Score:       </span><span class="gray">$stability_score/10</span>
</pre>
</body>
</html>
EOF

echo -e "${GRAY}Report saved as: $html_file${RESET}"

read -p "Open HTML report in browser? (y/n): " open_choice
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
    open "$html_file"
fi

echo -e "${GREEN}Done.${RESET}"
