#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - Unified macOS/Linux Edition
# =============================================================================
# This script automatically detects the platform and runs the appropriate
# USB enumeration method. It includes all logic in a single file.
# =============================================================================

# Colors
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'; GRAY='\033[0;90m'; NC='\033[0m'

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - Unified Edition${NC}"
echo -e "${CYAN}==============================================================================${NC}"

OS="$(uname -s)"
case "${OS}" in
    Linux*)
        PLATFORM="linux"
        echo -e "${GRAY}Platform: Linux ($(uname -r))${NC}"
        ;;
    Darwin*)
        PLATFORM="macos"
        echo -e "${GRAY}Platform: macOS ($(sw_vers -productVersion 2>/dev/null || echo "Unknown")) ($(uname -m))${NC}"
        ;;
    *)
        echo -e "${YELLOW}Platform: Unknown (limited support)${NC}"
        PLATFORM="unknown"
        ;;
esac
echo ""

# =============================================================================
# ADMIN CHECK (Works for both platforms)
# =============================================================================
USE_SUDO="n"
if [ "$EUID" -ne 0 ]; then
    echo -n "Run with sudo/admin for maximum detail? (y/n): "
    read USE_SUDO
    if [ "$USE_SUDO" = "y" ] || [ "$USE_SUDO" = "Y" ]; then
        echo -e "${YELLOW}Restarting with sudo...${NC}"
        exec sudo "$0" "$@"
        exit $?
    else
        echo -e "${YELLOW}Running without sudo.${NC}"
    fi
else
    echo -e "${GREEN}✓ Running with sudo privileges.${NC}"
fi
echo ""

# =============================================================================
# USB ENUMERATION - Platform Specific
# =============================================================================
DATE_STAMP=$(date +"%Y%m%d-%H%M%S")
OUT_TXT="/tmp/usb-tree-report-$DATE_STAMP.txt"
OUT_HTML="/tmp/usb-tree-report-$DATE_STAMP.html"

echo -e "${GRAY}Enumerating USB devices...${NC}"

TREE_OUTPUT=""
MAX_HOPS=0; HUBS=0; DEVICES=0

case $PLATFORM in
    macos)
        # macOS: Use system_profiler (reliable without sudo)
        device_list=$(system_profiler SPUSBDataType 2>/dev/null | \
            grep -v "^ " | grep -E ":" | \
            grep -v "Product ID:" | grep -v "Vendor ID:" | \
            grep -v "Serial Number:" | grep -v "Speed:" | \
            grep -v "Manufacturer:" | grep -v "Location ID:" | \
            sed -e 's/://g' -e 's/^[[:space:]]*//' | grep -v "^$")
        
        level=0
        while IFS= read -r device; do
            [ -z "$device" ] && continue
            prefix=$(printf '%*s' $((level * 4)) '' | sed 's/ /│   /g')
            if [ $level -gt 0 ]; then
                prefix="${prefix%│   }├── "
            else
                prefix="├── "
            fi
            
            if [[ "$device" == *[Hh]ub* ]]; then
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} [HUB] ← ${level} hops\n"
                HUBS=$((HUBS + 1))
            else
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} ← ${level} hops\n"
                DEVICES=$((DEVICES + 1))
            fi
            MAX_HOPS=$level
            level=$((level + 1))
        done <<< "$device_list"
        ;;
        
    linux)
        # Linux: Use lsusb
        if command -v lsusb &>/dev/null; then
            if [ "$EUID" -eq 0 ]; then
                # With sudo, get tree
                while IFS= read -r line; do
                    if [[ "$line" =~ ^([[:space:]]*)([^[:space:]].*)$ ]]; then
                        spaces="${#BASH_REMATCH[1]}"
                        level=$((spaces / 4))
                        device="${BASH_REMATCH[2]}"
                        
                        prefix=$(printf '%*s' $((level * 4)) '' | sed 's/ /│   /g')
                        [ $level -gt 0 ] && prefix="${prefix%│   }├── " || prefix="├── "
                        
                        if [[ "$device" == *[Hh]ub* ]]; then
                            TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} [HUB] ← ${level} hops\n"
                            HUBS=$((HUBS + 1))
                        else
                            TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} ← ${level} hops\n"
                            DEVICES=$((DEVICES + 1))
                        fi
                        [ $level -gt $MAX_HOPS ] && MAX_HOPS=$level
                    fi
                done < <(lsusb -t 2>/dev/null)
            else
                # Without sudo, simple list
                level=0
                while IFS= read -r device; do
                    [ -z "$device" ] && continue
                    TREE_OUTPUT="${TREE_OUTPUT}├── ${device} ← ${level} hops\n"
                    DEVICES=$((DEVICES + 1))
                done < <(lsusb 2>/dev/null | cut -d' ' -f7-)
                MAX_HOPS=0
            fi
        fi
        ;;
esac

# Fallback if no devices found
if [ -z "$TREE_OUTPUT" ]; then
    TREE_OUTPUT="├── No USB devices detected ← 0 hops\n"
fi

NUM_TIERS=$((MAX_HOPS + 1))
STABILITY_SCORE=$((9 - MAX_HOPS))
[ $STABILITY_SCORE -lt 1 ] && STABILITY_SCORE=1
[ $STABILITY_SCORE -gt 10 ] && STABILITY_SCORE=10

# =============================================================================
# STABILITY ASSESSMENT (Universal)
# =============================================================================
STATUS_SUMMARY=""
HOST_STATUS="STABLE"; HOST_COLOR="$GREEN"

# Define platform thresholds
declare -A THRESHOLDS=(
    ["Windows"]=5 ["Linux"]=4 ["Mac Intel"]=5 ["Mac Apple Silicon"]=3
    ["iPad USB-C (M-series)"]=2 ["iPhone USB-C"]=2
    ["Android Phone (Qualcomm)"]=3 ["Android Tablet (Exynos)"]=2
)

for plat in "Windows" "Linux" "Mac Intel" "Mac Apple Silicon" "iPad USB-C (M-series)" "iPhone USB-C" "Android Phone (Qualcomm)" "Android Tablet (Exynos)"; do
    t=${THRESHOLDS[$plat]}
    if [ $NUM_TIERS -le $t ]; then
        STATUS_SUMMARY="${STATUS_SUMMARY}$(printf "%-25s" "$plat") STABLE\n"
    elif [ $NUM_TIERS -le $((t + 2)) ]; then
        STATUS_SUMMARY="${STATUS_SUMMARY}$(printf "%-25s" "$plat") POTENTIALLY UNSTABLE\n"
        [ "$plat" = "Mac Apple Silicon" ] && [ "$HOST_STATUS" = "STABLE" ] && { HOST_STATUS="POTENTIALLY UNSTABLE"; HOST_COLOR="$YELLOW"; }
    else
        STATUS_SUMMARY="${STATUS_SUMMARY}$(printf "%-25s" "$plat") NOT STABLE\n"
        [ "$plat" = "Mac Apple Silicon" ] && { HOST_STATUS="NOT STABLE"; HOST_COLOR="$MAGENTA"; }
    fi
done

# =============================================================================
# OUTPUT
# =============================================================================
echo ""; echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE${NC}"; echo -e "${CYAN}==============================================================================${NC}"
echo -e "$TREE_OUTPUT"
echo ""; echo -e "${GRAY}Furthest jumps: $MAX_HOPS${NC}"
echo -e "${GRAY}Number of tiers: $NUM_TIERS${NC}"
echo -e "${GRAY}Total devices: $DEVICES${NC}"
echo -e "${GRAY}Total hubs: $HUBS${NC}"
echo ""; echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $MAX_HOPS hops)${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "$STATUS_SUMMARY"
echo ""; echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}HOST SUMMARY${NC}"; echo -e "${CYAN}==============================================================================${NC}"
echo -e "${GRAY}Host status:     ${NC}\c"; echo -e "${HOST_COLOR}$HOST_STATUS${NC}"
echo -e "${GRAY}Stability Score: ${GRAY}$STABILITY_SCORE/10${NC}"; echo ""

# Save text report
{
    echo "USB TREE REPORT - $DATE_STAMP"; echo ""; echo -e "$TREE_OUTPUT"; echo ""
    echo "Furthest jumps: $MAX_HOPS"; echo "Number of tiers: $NUM_TIERS"
    echo "Total devices: $DEVICES"; echo "Total hubs: $HUBS"; echo ""
    echo "STABILITY SUMMARY"; echo -e "$STATUS_SUMMARY"
    echo "HOST STATUS: $HOST_STATUS (Score: $STABILITY_SCORE/10)"
} > "$OUT_TXT"
echo -e "${GRAY}Report saved as: $OUT_TXT${NC}"

# =============================================================================
# HTML REPORT
# =============================================================================
{
    echo "<!DOCTYPE html><html><head><title>USB Tree Report</title>"
    echo "<style>body{background:#000;color:#e0e0e0;font-family:'Consolas',monospace;padding:20px;font-size:14px;}"
    echo "pre{margin:0;font-family:'Consolas',monospace;color:#e0e0e0;white-space:pre;}"
    echo ".cyan{color:#0ff;} .green{color:#0f0;} .yellow{color:#ff0;} .magenta{color:#f0f;} .gray{color:#c0c0c0;}</style></head><body><pre>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">USB TREE REPORT - $DATE_STAMP</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo ""; echo -e "$TREE_OUTPUT" | sed 's/\\033\[[0-9;]*m//g'; echo ""
    echo "<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>"
    echo "<span class=\"gray\">Number of tiers: $NUM_TIERS</span>"
    echo "<span class=\"gray\">Total devices: $DEVICES</span>"
    echo "<span class=\"gray\">Total hubs: $HUBS</span>"; echo ""
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo -e "$STATUS_SUMMARY" | while IFS= read -r line; do
        if [[ "$line" == *"STABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"green\">STABLE</span>"
        elif [[ "$line" == *"POTENTIALLY UNSTABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"yellow\">POTENTIALLY UNSTABLE</span>"
        elif [[ "$line" == *"NOT STABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"magenta\">NOT STABLE</span>"
        fi
    done
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">HOST SUMMARY</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "  <span class=\"gray\">Host status:     </span><span class=\"$([ "$HOST_STATUS" = "STABLE" ] && echo "green" || [ "$HOST_STATUS" = "POTENTIALLY UNSTABLE" ] && echo "yellow" || echo "magenta")\">$HOST_STATUS</span>"
    echo "  <span class=\"gray\">Stability Score: </span><span class=\"gray\">$STABILITY_SCORE/10</span>"
    echo "</pre></body></html>"
} > "$OUT_HTML"
echo -e "${GRAY}HTML report saved as: $OUT_HTML${NC}"

# =============================================================================
# FINAL PROMPTS
# =============================================================================
echo ""; echo -n "Open HTML report in browser? (y/n): "
read browser_answer
if [ "$browser_answer" = "y" ] || [ "$browser_answer" = "Y" ]; then
    if [ "$PLATFORM" = "macos" ]; then
        open "$OUT_HTML" 2>/dev/null
    else
        xdg-open "$OUT_HTML" 2>/dev/null
    fi || echo -e "${YELLOW}Could not open browser. File saved at: $OUT_HTML${NC}"
fi

echo ""; echo "Press any key to exit..."
read -n 1
exit 0
