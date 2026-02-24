#!/usr/bin/env bash
# =============================================================================
# USB Tree Diagnostic Tool - macOS Edition
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
HTML_PROMPT=$(get_config '.messages.en.htmlPrompt')

# Scoring config
MIN_SCORE=$(get_config '.scoring.minScore')
STABLE_THRESHOLD=$(get_config '.scoring.thresholds.stable')
POTENTIALLY_UNSTABLE_THRESHOLD=$(get_config '.scoring.thresholds.potentiallyUnstable')

echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}${WELCOME} - macOS EDITION${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${GRAY}${PLATFORM_MSG}: macOS ($(sw_vers -productVersion 2>/dev/null || echo "Unknown")) ($(uname -m))${RESET}"
echo ""

# Optional sudo prompt
read -p "$ADMIN_PROMPT " sudo_choice
echo ""

use_sudo=false
if [[ "$sudo_choice" =~ ^[Yy]$ ]]; then
    use_sudo=true
    echo -e "${CYAN}→ $ADMIN_YES${RESET}"
else
    echo -e "${YELLOW}$ADMIN_NO${RESET}"
fi

# Collect data
echo -e "${GRAY}${ENUMERATING}...${RESET}"

if $use_sudo; then
    raw_data=$(sudo system_profiler SPUSBDataType 2>/dev/null)
else
    raw_data=$(system_profiler SPUSBDataType 2>/dev/null)
fi

# Error check
if [[ -z "$raw_data" ]]; then
    echo -e "${YELLOW}$NO_DEVICES${RESET}"
    exit 1
fi

# Parse tree
tree_output=""
max_hops=0
hubs=0
devices=0

while IFS= read -r line; do
    # Calculate level from leading spaces (4 per indent)
    leading_spaces="${line%%[^[:space:]]*}"
    level=$(( ${#leading_spaces} / 4 ))

    # Trim and skip irrelevant lines
    trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
    if [[ -z "$trimmed" || "$trimmed" =~ ^(Product ID:|Vendor ID:|Serial Number:|Speed:|Manufacturer:|Location ID:|Current Available \(mA\):) ]]; then
        continue
    fi

    # Process device/hub lines (end with :)
    if [[ "$trimmed" =~ :$ ]]; then
        name="${trimmed%:}"  # Remove trailing colon
        name=$(echo "$name" | sed 's/^[[:space:]]*//')

        if [[ "$name" == *Hub* || "$name" == *hub* ]]; then
            display="[HUB] $name"
            ((hubs++))
        else
            display="$name"
            ((devices++))
        fi

        # Build prefix
        prefix=""
        for ((i=1; i<level; i++)); do prefix="${prefix}│   "; done
        if (( level > 0 )); then prefix="${prefix}├── "; fi

        tree_output+="${prefix}${display} ← ${level} hops\n"
        (( max_hops = level > max_hops ? level : max_hops ))
    fi
done <<< "$raw_data"

# Error check: Empty tree
if [[ -z "$tree_output" ]]; then
    echo -e "${YELLOW}Warning: No devices parsed. Using raw data.${RESET}"
    tree_output="$raw_data"
    echo "$raw_data" > /tmp/usb-raw-osx.txt
fi

num_tiers=$((max_hops + 1))
base_score=$(( 9 - max_hops ))
[[ $base_score -lt $MIN_SCORE ]] && base_score=$MIN_SCORE

# Determine platform for host status
if [[ "$(uname -m)" == "arm64" ]]; then
    platform_key="macAppleSilicon"
else
    platform_key="macIntel"
fi

# Output tree
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

# Stability section
echo -e "${CYAN}==============================================================================${RESET}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $max_hops hops)${RESET}"
echo -e "${CYAN}==============================================================================${RESET}"

# Parse platforms from config
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
echo -e "${HOST_STATUS}:           ${host_color}${host_status}${RESET}"
echo -e "${GRAY}${STABILITY_SCORE}:${RESET} $base_score/10"
echo ""

# HTML report
timestamp=$(date +"%Y%m%d-%H%M%S")
html_file="$HOME/usb-tree-report-macos-$timestamp.html"

# Build stability HTML
stability_html=""
for plat in $platforms; do
    name=$(get_config ".platformStability.$plat.name")
    rec=$(get_config ".platformStability.$plat.rec")
    max=$(get_config ".platformStability.$plat.max")
    
    if (( max_hops <= rec )); then
        col="green"
        status="STABLE"
    elif (( max_hops <= max )); then
        col="yellow"
        status="POTENTIALLY UNSTABLE"
    else
        col="magenta"
        status="NOT STABLE"
    fi
    
    stability_html+="  <span class=\"gray\">$(printf '%-25s' "$name")</span> <span class=\"$col\">$status</span>\n"
done

cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report - macOS - $timestamp</title>
    <style>
        body { background: $(get_config '.reporting.html.backgroundColor'); color: $(get_config '.reporting.html.textColor'); font-family: $(get_config '.reporting.html.fontFamily'); padding: 20px; font-size: $(get_config '.reporting.html.fontSize'); }
        pre { margin: 0; white-space: pre; }
        .cyan { color: $(get_config '.colors.cyan'); }
        .green { color: $(get_config '.colors.green'); }
        .yellow { color: $(get_config '.colors.yellow'); }
        .magenta { color: $(get_config '.colors.magenta'); }
        .gray { color: $(get_config '.colors.gray'); }
    </style>
</head>
<body>
<pre>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">USB TREE REPORT - macOS - $timestamp</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>

$tree_output

<span class="gray">${FURTHEST}: $max_hops</span>
<span class="gray">${TIERS}: $num_tiers</span>
<span class="gray">${TOTAL_DEVICES}: $devices</span>
<span class="gray">${TOTAL_HUBS}: $hubs</span>

<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">STABILITY PER PLATFORM (based on $max_hops hops)</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
$stability_html

<span class="cyan">$(get_config '.reporting.html.separator')</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">$(get_config '.reporting.html.separator')</span>
  <span class="gray">${HOST_STATUS}:           </span><span class="${host_color:2:-4}">$host_status</span>
  <span class="gray">${STABILITY_SCORE}:       </span><span class="gray">$base_score/10</span>
</pre>
</body>
</html>
EOF

echo -e "${GRAY}${REPORT_SAVED}: $html_file${RESET}"

read -p "$HTML_PROMPT " open_choice
if [[ "$open_choice" =~ ^[Yy]$ ]]; then
    open "$html_file"
fi

echo -e "${GREEN}Done.${RESET}"
