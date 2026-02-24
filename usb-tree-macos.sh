#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition (DEFINITELY FIXED)
# =============================================================================
# Uses ioreg -p IOUSB for accurate USB tree detection
# =============================================================================

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
NC='\033[0m'

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - MACOS EDITION${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo -e "${GRAY}Platform: macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))${NC}"
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
# USB DEVICE ENUMERATION
# =============================================================================
DATE_STAMP=$(date +"%Y%m%d-%H%M%S")
OUT_TXT="/tmp/usb-tree-report-$DATE_STAMP.txt"
OUT_HTML="/tmp/usb-tree-report-$DATE_STAMP.html"

echo -e "${GRAY}Enumerating USB devices...${NC}"

# Clear variables
TREE_OUTPUT=""
MAX_HOPS=0
HUBS=0
DEVICES=0

# Use ioreg to get USB tree
echo "Getting USB devices from ioreg..."

# Run ioreg and process output
ioreg_output=$(ioreg -p IOUSB -r -w 0 -l 2>/dev/null)

# Process each line
current_line=""
while IFS= read -r line; do
    # Look for device entries
    if [[ "$line" == *"+-o"* ]]; then
        # Extract device name - everything between +-o and @ or <
        if [[ "$line" =~ \+\-o\ ([^@<]+) ]]; then
            device="${BASH_REMATCH[1]}"
            device=$(echo "$device" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Count pipes to determine level
            pipes=$(echo "$line" | grep -o "\|" | wc -l)
            level=$((pipes / 2))
            
            # Check if it's a hub
            if [[ "$device" == *"Hub"* ]] || [[ "$device" == *"HUB"* ]] || [[ "$device" == *"hub"* ]]; then
                is_hub="yes"
                HUBS=$((HUBS + 1))
            else
                is_hub="no"
                DEVICES=$((DEVICES + 1))
            fi
            
            # Build tree prefix
            prefix=""
            for ((i=0; i<level; i++)); do
                if [ $i -eq $((level-1)) ]; then
                    prefix="${prefix}├── "
                else
                    prefix="${prefix}│   "
                fi
            done
            
            # Add to tree output
            if [ "$is_hub" = "yes" ]; then
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} [HUB] ← ${level} hops\n"
            else
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} ← ${level} hops\n"
            fi
            
            # Update max hops
            if [ $level -gt $MAX_HOPS ]; then
                MAX_HOPS=$level
            fi
        fi
    fi
done <<< "$ioreg_output"

# If no devices found with ioreg, try system_profiler
if [ -z "$TREE_OUTPUT" ]; then
    echo "Trying system_profiler as fallback..."
    profiler_output=$(system_profiler SPUSBDataType 2>/dev/null | grep -v ":" | grep -v "^[[:space:]]*$" | grep -v "Product ID" | grep -v "Vendor ID" | grep -v "Speed" | grep -v "Manufacturer" | grep -v "Location ID" | grep -v "Serial Number" | sed -e 's/^[[:space:]]*//')
    
    level=0
    while IFS= read -r device; do
        if [ -n "$device" ]; then
            if [[ "$device" == *"Hub"* ]] || [[ "$device" == *"HUB"* ]] || [[ "$device" == *"hub"* ]]; then
                TREE_OUTPUT="${TREE_OUTPUT}├── ${device} [HUB] ← ${level} hops\n"
                HUBS=$((HUBS + 1))
            else
                TREE_OUTPUT="${TREE_OUTPUT}├── ${device} ← ${level} hops\n"
                DEVICES=$((DEVICES + 1))
            fi
            level=$((level + 1))
            MAX_HOPS=$level
        fi
    done <<< "$profiler_output"
fi

# If STILL no devices, show message
if [ -z "$TREE_OUTPUT" ]; then
    TREE_OUTPUT="├── No USB devices detected ← 0 hops\n"
fi

NUM_TIERS=$((MAX_HOPS + 1))
STABILITY_SCORE=$((9 - MAX_HOPS))
[ $STABILITY_SCORE -lt 1 ] && STABILITY_SCORE=1
[ $STABILITY_SCORE -gt 10 ] && STABILITY_SCORE=10

# =============================================================================
# STABILITY ASSESSMENT
# =============================================================================
# Platform thresholds: Windows|Linux|Mac Intel|Mac Apple Silicon|iPad|iPhone|Android Phone|Android Tablet
STATUS_SUMMARY=""
HOST_STATUS="STABLE"
HOST_COLOR="$GREEN"

# Check each platform
if [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Windows                   STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Windows                   NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

if [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Linux                     STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Linux                     NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

if [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Intel                 STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Intel                 NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

if [ $NUM_TIERS -le 3 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Apple Silicon         STABLE\n"
elif [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Apple Silicon         POTENTIALLY UNSTABLE\n"
    if [ "$HOST_STATUS" = "STABLE" ]; then
        HOST_STATUS="POTENTIALLY UNSTABLE"
        HOST_COLOR="$YELLOW"
    fi
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Apple Silicon         NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

if [ $NUM_TIERS -le 2 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     STABLE\n"
elif [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     POTENTIALLY UNSTABLE\n"
    if [ "$HOST_STATUS" = "STABLE" ]; then
        HOST_STATUS="POTENTIALLY UNSTABLE"
        HOST_COLOR="$YELLOW"
    fi
else
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

if [ $NUM_TIERS -le 2 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              STABLE\n"
elif [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              NOT STABLE\n"
fi

if [ $NUM_TIERS -le 3 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  STABLE\n"
elif [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  NOT STABLE\n"
fi

if [ $NUM_TIERS -le 2 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Tablet (Exynos)   STABLE\n"
elif [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Tablet (Exynos)   POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Tablet (Exynos)   NOT STABLE\n"
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
# Convert status summary to HTML
HTML_STATUS=""
while IFS= read -r line; do
    if [ -n "$line" ]; then
        if [[ "$line" == *"STABLE"* ]]; then
            HTML_STATUS="${HTML_STATUS}  <span class='gray'>$(echo "$line" | cut -c1-25)</span> <span class='green'>STABLE</span>\n"
        elif [[ "$line" == *"POTENTIALLY UNSTABLE"* ]]; then
            HTML_STATUS="${HTML_STATUS}  <span class='gray'>$(echo "$line" | cut -c1-25)</span> <span class='yellow'>POTENTIALLY UNSTABLE</span>\n"
        elif [[ "$line" == *"NOT STABLE"* ]]; then
            HTML_STATUS="${HTML_STATUS}  <span class='gray'>$(echo "$line" | cut -c1-25)</span> <span class='magenta'>NOT STABLE</span>\n"
        fi
    fi
done <<< "$STATUS_SUMMARY"

# Clean tree output for HTML
CLEAN_TREE=$(echo -e "$TREE_OUTPUT" | sed 's/\\033\[[0-9;]*m//g')

# Determine host color for HTML
HOST_HTML_COLOR="green"
if [ "$HOST_STATUS" = "POTENTIALLY UNSTABLE" ]; then
    HOST_HTML_COLOR="yellow"
elif [ "$HOST_STATUS" = "NOT STABLE" ]; then
    HOST_HTML_COLOR="magenta"
fi

# Create HTML file
cat > "$OUT_HTML" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report</title>
    <style>
        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', monospace; padding: 20px; font-size: 14px; }
        pre { margin: 0; font-family: 'Consolas', monospace; color: #e0e0e0; white-space: pre; }
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
<span class="cyan">USB TREE REPORT - $DATE_STAMP</span>
<span class="cyan">==============================================================================</span>

$CLEAN_TREE

<span class="gray">Furthest jumps: $MAX_HOPS</span>
<span class="gray">Number of tiers: $NUM_TIERS</span>
<span class="gray">Total devices: $DEVICES</span>
<span class="gray">Total hubs: $HUBS</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>
<span class="cyan">==============================================================================</span>
$(echo -e "$HTML_STATUS")
<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class="gray">Host status:     </span><span class="$HOST_HTML_COLOR">$HOST_STATUS</span>
  <span class="gray">Stability Score: </span><span class="gray">$STABILITY_SCORE/10</span>
</pre>
</body>
</html>
EOF

echo -e "${GRAY}HTML report saved as: $OUT_HTML${NC}"

# =============================================================================
# ASK TO OPEN BROWSER - SIMPLE AND CLEAN
# =============================================================================
echo ""
echo -n "Open HTML report in browser? (y/n): "
read browser_answer
if [ "$browser_answer" = "y" ]; then
    open "$OUT_HTML" 2>/dev/null || echo "Could not open browser. File saved at: $OUT_HTML"
fi

# =============================================================================
# EXIT
# =============================================================================
echo ""
echo "Press any key to exit..."
read -n 1
exit 0
