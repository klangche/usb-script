#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition (FIXED with ioreg)
# =============================================================================
# Uses ioreg -p IOUSB for accurate USB tree detection
# Identical output format to Windows version for side-by-side comparison
# =============================================================================

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m'

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - MACOS EDITION${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${GRAY}Platform: macOS $(sw_vers -productVersion 2>/dev/null || echo "Unknown") ($(uname -m))${NC}"
echo ""

# =============================================================================
# ADMIN CHECK
# =============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -n "Run with sudo for maximum detail? (y/n): "
    read adminChoice
    
    if [ "$adminChoice" = "y" ]; then
        echo -e "${YELLOW}Restarting with sudo...${NC}"
        sudo "$0" "$@"
        exit $?
    else
        echo -e "${YELLOW}Running without sudo (basic mode).${NC}"
    fi
else
    echo -e "${GREEN}✓ Running with sudo privileges.${NC}"
fi
echo ""

# =============================================================================
# USB DEVICE ENUMERATION - Using ioreg for accurate detection
# =============================================================================
DATE_STAMP=$(date +"%Y%m%d-%H%M%S")
OUT_TXT="/tmp/usb-tree-report-$DATE_STAMP.txt"
OUT_HTML="/tmp/usb-tree-report-$DATE_STAMP.html"

echo -e "${GRAY}Enumerating USB devices...${NC}"

# Use ioreg to get USB tree
if command -v ioreg &> /dev/null; then
    # Get USB tree from ioreg
    USB_IOREG=$(ioreg -p IOUSB -r -w 0 -l 2>/dev/null)
    
    # Parse the tree
    TREE_OUTPUT=""
    MAX_HOPS=0
    HUBS=0
    DEVICES=0
    
    # Process each line
    current_level=0
    while IFS= read -r line; do
        # Count | symbols to determine level
        level=$(echo "$line" | grep -o "\|" | wc -l)
        level=$((level / 2))  # Each level adds one pipe
        
        # Extract device name
        if [[ "$line" =~ \+\-o\ ([^@<]+) ]]; then
            device_name="${BASH_REMATCH[1]}"
            device_name=$(echo "$device_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Check if it's a hub
            is_hub=false
            if [[ "$device_name" == *"Hub"* ]] || [[ "$device_name" == *"HUB"* ]] || [[ "$device_name" == *"hub"* ]]; then
                is_hub=true
                HUBS=$((HUBS + 1))
            else
                DEVICES=$((DEVICES + 1))
            fi
            
            # Build tree prefixes
            if [ $level -gt 0 ]; then
                prefix=""
                for ((i=0; i<level; i++)); do
                    if [ $i -eq $((level-1)) ]; then
                        prefix="${prefix}├── "
                    else
                        prefix="${prefix}│   "
                    fi
                done
            else
                prefix="├── "
            fi
            
            # Add to tree output
            if [ "$is_hub" = true ]; then
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device_name} [HUB] ← ${level} hops\n"
            else
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device_name} ← ${level} hops\n"
            fi
            
            # Update max hops
            if [ $level -gt $MAX_HOPS ]; then
                MAX_HOPS=$level
            fi
        fi
    done <<< "$USB_IOREG"
fi

# If no devices found, try system_profiler as fallback
if [ -z "$TREE_OUTPUT" ] && command -v system_profiler &> /dev/null; then
    USB_DATA=$(system_profiler SPUSBDataType 2>/dev/null | grep -v ":" | grep -v "^[[:space:]]*$" | sed -e 's/^[[:space:]]*//' | grep -v "^Product ID" | grep -v "^Vendor ID" | grep -v "^Speed" | grep -v "^Manufacturer" | grep -v "^Location ID" | grep -v "^Serial Number")
    
    level=0
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if [[ "$line" == *"Hub"* ]] || [[ "$line" == *"HUB"* ]] || [[ "$line" == *"hub"* ]]; then
                TREE_OUTPUT="${TREE_OUTPUT}├── ${line} [HUB] ← ${level} hops\n"
                HUBS=$((HUBS + 1))
            else
                TREE_OUTPUT="${TREE_OUTPUT}├── ${line} ← ${level} hops\n"
                DEVICES=$((DEVICES + 1))
            fi
            level=$((level + 1))
            MAX_HOPS=$level
        fi
    done <<< "$USB_DATA"
fi

# If still no devices found
if [ -z "$TREE_OUTPUT" ]; then
    TREE_OUTPUT="├── No USB devices detected ← 0 hops\n"
    MAX_HOPS=0
    DEVICES=0
    HUBS=0
fi

NUM_TIERS=$((MAX_HOPS + 1))
STABILITY_SCORE=$((9 - MAX_HOPS))
[ $STABILITY_SCORE -lt 1 ] && STABILITY_SCORE=1
[ $STABILITY_SCORE -gt 10 ] && STABILITY_SCORE=10

# =============================================================================
# STABILITY ASSESSMENT
# =============================================================================
cat > /tmp/platform_status.txt << 'EOF'
Windows|5|7
Linux|4|6
Mac Intel|5|7
Mac Apple Silicon|3|5
iPad USB-C (M-series)|2|4
iPhone USB-C|2|4
Android Phone (Qualcomm)|3|5
Android Tablet (Exynos)|2|4
EOF

STATUS_LINES=""
while IFS='|' read plat rec max; do
    if [ $NUM_TIERS -le $rec ]; then
        status="STABLE"
    elif [ $NUM_TIERS -le $max ]; then
        status="POTENTIALLY UNSTABLE"
    else
        status="NOT STABLE"
    fi
    STATUS_LINES="${STATUS_LINES}${plat}|${status}\n"
done < /tmp/platform_status.txt

# Format for terminal
STATUS_SUMMARY=""
while IFS='|' read plat status; do
    if [ -n "$plat" ] && [ -n "$status" ]; then
        printf -v padded "%-25s" "$plat"
        STATUS_SUMMARY="${STATUS_SUMMARY}${padded} ${status}\n"
    fi
done < <(echo -e "$STATUS_LINES" | grep -v '^$')

# Determine host status
MAC_AS_STATUS=$(echo -e "$STATUS_LINES" | grep "Mac Apple Silicon" | cut -d'|' -f2)
if [ "$MAC_AS_STATUS" = "NOT STABLE" ]; then
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
elif [ "$MAC_AS_STATUS" = "POTENTIALLY UNSTABLE" ]; then
    HOST_STATUS="POTENTIALLY UNSTABLE"
    HOST_COLOR="$YELLOW"
else
    if echo -e "$STATUS_LINES" | grep -v "Mac Apple Silicon" | grep -q "NOT STABLE"; then
        HOST_STATUS="NOT STABLE"
        HOST_COLOR="$MAGENTA"
    elif echo -e "$STATUS_LINES" | grep -v "Mac Apple Silicon" | grep -q "POTENTIALLY UNSTABLE"; then
        HOST_STATUS="POTENTIALLY UNSTABLE"
        HOST_COLOR="$YELLOW"
    else
        HOST_STATUS="STABLE"
        HOST_COLOR="$GREEN"
    fi
fi

# =============================================================================
# TERMINAL OUTPUT
# =============================================================================
echo ""
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "$TREE_OUTPUT"
echo ""
echo -e "${GRAY}Furthest jumps: $MAX_HOPS${NC}"
echo -e "${GRAY}Number of tiers: $NUM_TIERS${NC}"
echo -e "${GRAY}Total devices: $DEVICES${NC}"
echo -e "${GRAY}Total hubs: $HUBS${NC}"
echo ""
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}STABILITY PER PLATFORM (based on $MAX_HOPS hops)${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "$STATUS_SUMMARY"
echo ""
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}HOST SUMMARY${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${GRAY}Host status:     ${NC}\c"
echo -e "${HOST_COLOR}$HOST_STATUS${NC}"
echo -e "${GRAY}Stability Score: ${GRAY}$STABILITY_SCORE/10${NC}"
echo ""

# =============================================================================
# SAVE TEXT REPORT
# =============================================================================
{
    echo "USB TREE REPORT - $DATE_STAMP"
    echo ""
    echo -e "$TREE_OUTPUT"
    echo ""
    echo "Furthest jumps: $MAX_HOPS"
    echo "Number of tiers: $NUM_TIERS"
    echo "Total devices: $DEVICES"
    echo "Total hubs: $HUBS"
    echo ""
    echo "STABILITY SUMMARY"
    echo -e "$STATUS_SUMMARY"
    echo "HOST STATUS: $HOST_STATUS (Score: $STABILITY_SCORE/10)"
} > "$OUT_TXT"

echo -e "${GRAY}Report saved as: $OUT_TXT${NC}"

# =============================================================================
# HTML REPORT
# =============================================================================
PLATFORM_HTML=""
while IFS='|' read plat status; do
    if [ -n "$plat" ] && [ -n "$status" ]; then
        case "$status" in
            "STABLE") color="green" ;;
            "POTENTIALLY UNSTABLE") color="yellow" ;;
            "NOT STABLE") color="magenta" ;;
        esac
        PLATFORM_HTML="${PLATFORM_HTML}  <span class='gray'>$(printf "%-25s" "$plat")</span> <span class='$color'>$status</span>\n"
    fi
done < <(echo -e "$STATUS_LINES" | grep -v '^$')

HOST_COLOR_HTML=""
if [[ "$HOST_COLOR" == *"32m"* ]]; then
    HOST_COLOR_HTML="green"
elif [[ "$HOST_COLOR" == *"33m"* ]]; then
    HOST_COLOR_HTML="yellow"
elif [[ "$HOST_COLOR" == *"35m"* ]]; then
    HOST_COLOR_HTML="magenta"
else
    HOST_COLOR_HTML="gray"
fi

CLEAN_TREE=$(echo -e "$TREE_OUTPUT" | sed 's/\\033\[[0-9;]*m//g')

HTML_CONTENT="<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report</title>
    <style>
        body { 
            background: #000000; 
            color: #e0e0e0; 
            font-family: 'Consolas', 'Courier New', monospace; 
            padding: 20px;
            font-size: 14px;
        }
        pre { 
            margin: 0; 
            font-family: 'Consolas', 'Courier New', monospace;
            color: #e0e0e0;
            white-space: pre;
        }
        .cyan { color: #00ffff; }
        .green { color: #00ff00; }
        .yellow { color: #ffff00; }
        .magenta { color: #ff00ff; }
        .white { color: #ffffff; }
        .gray { color: #c0c0c0; }
    </style>
</head>
<body>
<pre>
<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">USB TREE REPORT - $DATE_STAMP</span>
<span class=\"cyan\">==============================================================================</span>

$CLEAN_TREE

<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>
<span class=\"gray\">Number of tiers: $NUM_TIERS</span>
<span class=\"gray\">Total devices: $DEVICES</span>
<span class=\"gray\">Total hubs: $HUBS</span>

<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>
<span class=\"cyan\">==============================================================================</span>
$(echo -e "$PLATFORM_HTML")
<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">HOST SUMMARY</span>
<span class=\"cyan\">==============================================================================</span>
  <span class=\"gray\">Host status:     </span><span class=\"$HOST_COLOR_HTML\">$HOST_STATUS</span>
  <span class=\"gray\">Stability Score: </span><span class=\"gray\">$STABILITY_SCORE/10</span>
</pre>
</body>
</html>"

echo "$HTML_CONTENT" > "$OUT_HTML"
echo -e "${GRAY}HTML report saved as: $OUT_HTML${NC}"

# =============================================================================
# ASK TO OPEN BROWSER - FIXED: No syntax error
# =============================================================================
echo ""
echo -n "Open HTML report in browser? (y/n): "
read browser_choice
if [ "$browser_choice" = "y" ]; then
    open "$OUT_HTML" 2>/dev/null || echo -e "${YELLOW}Could not open browser. File saved at: $OUT_HTML${NC}"
fi

# =============================================================================
# Exit with proper message
# =============================================================================
echo ""
echo -e "${GRAY}Press any key to exit...${NC}"
read -n 1
