#!/usr/bin/env bash
# =============================================================================
# USB Tree Diagnostic Tool - Linux Edition
# =============================================================================
# Uses centralized configuration from usb-tree-config.json
# =============================================================================

# Load configuration
CONFIG_URL="https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-config.json"
CONFIG=$(curl -s "$CONFIG_URL")

# Helper function to get config values
get_config() {
    echo "$CONFIG" | jq -r "$1"
}

# Colors from config
CYAN=$(get_config '.colors.cyan')
GREEN=$(get_config '.colors.green')
YELLOW=$(get_config '.colors.yellow')
MAGENTA=$(get_config '.colors.magenta')
GRAY=$(get_config '.colors.gray')
RESET='\033[0m'

# Messages
WELCOME=$(get_config '.messages.en.welcome')
PLATFORM_MSG=$(get_config '.messages.en.platform')
NO_DEVICES=$(get_config '.messages.en.noDevices')
ADMIN_PROMPT=$(get_config '.messages.en.adminPrompt')
ADMIN_YES=$(get_config '.messages.en.adminYes')
ADMIN_NO=$(get_config '.messages.en.adminNo')
ENUMERATING=$(get_config '.messages.en.enumerating')
FOUND=$(get_config '.messages.en.found')
DEVICES=$(get_config '.messages.en.devices')
HUBS=$(get_config '.messages.en.hubs')
FURTHEST=$(get_config '.messages.en.furthestJumps')
TIERS=$(get_config '.messages.en.numberOfTiers')
TOTAL_DEVICES=$(get_config '.messages.en.totalDevices')
TOTAL_HUBS=$(get_config '.messages.en.totalHubs')
HOST_STATUS=$(get_config '.messages.en.hostStatus')
STABILITY_SCORE=$(get_config '.messages.en.stabilityScore')
REPORT_SAVED=$(get_config '.messages.en.reportSaved')
HTML_SAVED=$(get_config '.messages.en.htmlSaved')
EXIT_PROMPT=$(get_config '.messages.en.exitPrompt')

# Scoring config
MIN_SCORE=$(get_config '.scoring.minScore')
STABLE_THRESHOLD=$(get_config '.scoring.thresholds.stable')
POTENTIALLY_UNSTABLE_THRESHOLD=$(get_config '.scoring.thresholds.potentiallyUnstable')

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}${WELCOME} - LINUX EDITION${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${GRAY}${PLATFORM_MSG}: Linux ($(uname -r)) ($(uname -m))${RESET}"
echo ""

# Check for lsusb
if ! command -v lsusb >/dev/null 2>&1; then
    echo -e "${YELLOW}Error: lsusb not found. Install usbutils (e.g., sudo apt install usbutils).${RESET}"
    exit 1
fi

# Prompt for sudo
read -p "$ADMIN_PROMPT " sudo_choice
echo ""

use_sudo=false
if [[ "$sudo_choice" =~ ^[Yy]$ ]]; then
    use_sudo=true
    echo -e "${CYAN}→ $ADMIN_YES${RESET}"
else
    echo -e "${YELLOW}$ADMIN_NO${RESET}"
fi

# Collect USB data
echo -e "${GRAY}${ENUMERATING}...${RESET}"

if $use_sudo; then
    raw_tree=$(sudo lsusb -t 2>/dev/null)
    raw_list=$(sudo lsusb 2>/dev/null)
else
    raw_tree=$(lsusb -t 2>/dev/null || echo "No tree available without sudo")
    raw_list=$(lsusb 2>/dev/null)
fi

if [[ -z "$raw_list" ]]; then
    echo -e "${YELLOW}$NO_DEVICES${RESET}"
    exit 1
fi

usb_data="${raw_tree:-$raw_list}"

# Parse tree
tree_output=""
max_hops=0
hubs=0
devices=0

while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    
    leading="${line%%[![:space:]]*}"
    level=$(( ${#leading} / 4 ))
    
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
    
    if [[ "$trimmed" =~ Hub || "$trimmed" =~ hub ]]; then
        display="[HUB] $trimmed"
        ((hubs++))
    else
        display="$trimmed"
        ((devices++))
    fi
    
    prefix=""
    for ((i=1; i<=level; i++)); do prefix="${prefix}│   "; done
    if (( level > 0 )); then prefix="${prefix}└── "; fi
    
    tree_output+="${prefix}${display} ← ${level} hops\n"
    (( max_hops = level > max_hops ? level : max_hops ))
done <<< "$usb_data"

if [[ -z "$tree_output" ]]; then
    echo -e "${YELLOW}Warning: Tree parsing failed. Falling back to raw data.${RESET}"
    tree_output="$usb_data"
fi

num_tiers=$((max_hops + 1))
base_score=$(( 9 - max_hops ))
[[ $base_score -lt $MIN_SCORE ]] && base_score=$MIN_SCORE

# Determine platform for stability table
if [[ "$(uname -m)" == "aarch64" ]]; then
    platform_key="linuxArm"
else
    platform_key="linux"
fi

# Build platform stability table from config
echo ""
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}USB TREE${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "$tree_output"
echo ""
echo -e "${GRAY}${FURTHEST}: $max_hops${RESET}"
echo -e "${GRAY}${TIERS}: $num_tiers${RESET}"
echo -e "${GRAY}${TOTAL_DEVICES}: $devices${RESET}"
echo -e "${GRAY}${TOTAL_HUBS}: $hubs${RESET}"
echo ""

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $max_hops hops)${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"

# Parse platforms from config and display
platforms=$(get_config '.platformStability | keys[]')
host_status="STABLE"
host_color=$GREEN

for plat in $platforms; do
    name=$(get_config ".platformStability.$plat.name")
    rec=$(get_config ".platformStability.$plat.rec")
    max=$(get_config ".platformStability.$plat.max")
    
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
    
    # Track Apple Silicon for host status
    if [[ "$plat" == "macAppleSilicon" ]]; then
        host_status="$status"
        host_color="$color"
    fi
    
    printf "  %-25s ${color}%s${RESET}\n" "$name" "$status"
done

echo ""
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}HOST SUMMARY${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${HOST_STATUS}: ${host_color}${host_status}${RESET}"
echo -e "${GRAY}${STABILITY_SCORE}:${RESET} $base_score/10"
echo ""

# Generate HTML report
timestamp=$(date +"%Y%m%d-%H%M%S")
html_file="$HOME/usb-tree-report-linux-$timestamp.html"

# Build stability HTML
stability_html=""
for plat in $platforms; do
    name=$(get_config ".platformStability.$plat.name")
    rec=$(get_config ".platformStability.$plat.rec")
    max=$(get_config ".platformStability.$plat.max")
    
    if (( max_hops <= rec )); then
        col="green"
    elif (( max_hops <= max )); then
        col="yellow"
    else
        col="magenta"
    fi
    
    stability_html+="  <span class=\"gray\">$(printf '%-25s' "$name")</span> <span class=\"$col\">$status</span>\n"
done

cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - Linux - $timestamp</title>
    <style>
        body { background: $(get_config '.reporting.html.backgroundColor'); color: $(get_config '.reporting.html.textColor'); font-family: $(get_config '.reporting.html.fontFamily'); padding: 20px; font-size: $(get_config '.reporting.html.fontSize'); }
        pre { white-space: pre; }
        .cyan { color: $(get_config '.colors.cyan'); }
        .green { color: $(get_config '.colors.green'); }
        .yellow { color: $(get_config '.colors.yellow'); }
        .magenta { color: $(get_config '.colors.magenta'); }
        .gray { color: $(get_config '.colors.gray'); }
    </style>
</head>
<body><pre>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">USB TREE REPORT - Linux - $timestamp</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>

$(if $use_sudo; then echo "$tree_output"; else echo "(Basic list - run with sudo for tree)"; echo "$usb_data"; fi)

<span class="gray">${FURTHEST}: $max_hops</span>
<span class="gray">${TIERS}: $num_tiers</span>
<span class="gray">${TOTAL_DEVICES}: $devices</span>
<span class="gray">${TOTAL_HUBS}: $hubs</span>

<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">STABILITY PER PLATFORM</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
$stability_html

<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
  <span class="gray">${HOST_STATUS}:     </span><span class="${host_color:2:-4}">$host_status</span>
  <span class="gray">${STABILITY_SCORE}: </span><span class="gray">$base_score/10</span>
</pre></body></html>
EOF

echo -e "${GRAY}${REPORT_SAVED}: $html_file${RESET}"

read -p "$(get_config '.messages.en.htmlPrompt') " open_choice
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
    if command -v xdg-open >/dev/null; then
        xdg-open "$html_file"
    else
        echo -e "${YELLOW}xdg-open not found — open $html_file manually${RESET}"
    fi
fi

echo -e "${GREEN}Done.${RESET}"
