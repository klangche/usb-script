#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition
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
# ASK FOR ADMIN - FIXED: Actually asks the question
# =============================================================================
USE_SUDO="n"
if [ "$EUID" -ne 0 ]; then
    echo -n "Run with sudo for maximum detail? (y/n): "
    read USE_SUDO
    if [ "$USE_SUDO" = "y" ]; then
        echo -e "${YELLOW}Restarting with sudo...${NC}"
        sudo "$0" "$@"
        exit $?
    else
        echo -e "${YELLOW}Running without sudo.${NC}"
    fi
else
    echo -e "${GREEN}✓ Running with sudo privileges.${NC}"
fi
echo ""

# =============================================================================
# USB DEVICE ENUMERATION - Using ioreg
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
ioreg_output=$(ioreg -p IOUSB -r -w 0 -l 2>/dev/null)

# Process each line
while IFS= read -r line; do
    # Look for device entries
    if [[ "$line" == *"+-o"* ]]; then
        # Extract device name
        if [[ "$line" =~ \+\-o\ ([^@<]+) ]]; then
            device="${BASH_REMATCH[1]}"
            device=$(echo "$device" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Skip if empty
            if [ -z "$device" ]; then
                continue
            fi
            
            # Count pipes to determine level
            pipes=$(echo "$line" | grep -o "\|" | wc -l)
            level=$((pipes))
            
            # Build tree prefix
            prefix=""
            for ((i=0; i<level; i++)); do
                if [ $i -eq $((level-1)) ]; then
                    prefix="${prefix}├── "
                else
                    prefix="${prefix}│   "
                fi
            done
            
            # Check if it's a hub
            if [[ "$device" == *"Hub"* ]] || [[ "$device" == *"HUB"* ]] || [[ "$device" == *"hub"* ]]; then
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} [HUB] ← ${level} hops\n"
                HUBS=$((HUBS + 1))
            else
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} ← ${level} hops\n"
                DEVICES=$((DEVICES + 1))
            fi
            
            # Update max hops
            if [ $level -gt $MAX_HOPS ]; then
                MAX_HOPS=$level
            fi
        fi
    fi
done <<< "$ioreg_output"

# If no devices found with ioreg, show what we got from ioreg for debugging
if [ -z "$TREE_OUTPUT" ]; then
    TREE_OUTPUT="├── No USB devices detected ← 0 hops\n"
    echo -e "${YELLOW}Debug: ioreg output was:${NC}" >&2
    echo "$ioreg_output" | head -20 >&2
fi

NUM_TIERS=$((MAX_HOPS + 1))
STABILITY_SCORE=$((9 - MAX_HOPS))
[ $STABILITY_SCORE -lt 1 ] && STABILITY_SCORE=1
[ $STABILITY_SCORE -gt 10 ] && STABILITY_SCORE=10

# =============================================================================
# STABILITY ASSESSMENT
# =============================================================================
STATUS_SUMMARY=""
HOST_STATUS="STABLE"
HOST_COLOR="$GREEN"

# Windows
if [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Windows                   STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Windows                   NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

# Linux
if [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Linux                     STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Linux                     NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

# Mac Intel
if [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Intel                 STABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Mac Intel                 NOT STABLE\n"
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
fi

# Mac Apple Silicon
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

# iPad
if [ $NUM_TIERS -le 2 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     STABLE\n"
elif [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}iPad USB-C (M-series)     NOT STABLE\n"
fi

# iPhone
if [ $NUM_TIERS -le 2 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              STABLE\n"
elif [ $NUM_TIERS -le 4 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}iPhone USB-C              NOT STABLE\n"
fi

# Android Phone
if [ $NUM_TIERS -le 3 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  STABLE\n"
elif [ $NUM_TIERS -le 5 ]; then
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  POTENTIALLY UNSTABLE\n"
else
    STATUS_SUMMARY="${STATUS_SUMMARY}Android Phone (Qualcomm)  NOT STABLE\n"
fi

# Android Tablet
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
# Create HTML file with heredoc (simpler, no syntax errors)
cat > "$OUT_HTML" << 'EOF'
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
EOF

# Append dynamic content
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">USB TREE REPORT - $DATE_STAMP</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"
echo "" >> "$OUT_HTML"
echo -e "$TREE_OUTPUT" | sed 's/\\033\[[0-9;]*m//g' >> "$OUT_HTML"
echo "" >> "$OUT_HTML"
echo "<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>" >> "$OUT_HTML"
echo "<span class=\"gray\">Number of tiers: $NUM_TIERS</span>" >> "$OUT_HTML"
echo "<span class=\"gray\">Total devices: $DEVICES</span>" >> "$OUT_HTML"
echo "<span class=\"gray\">Total hubs: $HUBS</span>" >> "$OUT_HTML"
echo "" >> "$OUT_HTML"
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"

# Add platform status lines
while IFS= read -r line; do
    if [ -n "$line" ]; then
        if [[ "$line" == *"STABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"green\">STABLE</span>" >> "$OUT_HTML"
        elif [[ "$line" == *"POTENTIALLY UNSTABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"yellow\">POTENTIALLY UNSTABLE</span>" >> "$OUT_HTML"
        elif [[ "$line" == *"NOT STABLE"* ]]; then
            echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"magenta\">NOT STABLE</span>" >> "$OUT_HTML"
        fi
    fi
done <<< "$STATUS_SUMMARY"

# Add host summary
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">HOST SUMMARY</span>" >> "$OUT_HTML"
echo "<span class=\"cyan\">==============================================================================</span>" >> "$OUT_HTML"

if [ "$HOST_STATUS" = "STABLE" ]; then
    echo "  <span class=\"gray\">Host status:     </span><span class=\"green\">$HOST_STATUS</span>" >> "$OUT_HTML"
elif [ "$HOST_STATUS" = "POTENTIALLY UNSTABLE" ]; then
    echo "  <span class=\"gray\">Host status:     </span><span class=\"yellow\">$HOST_STATUS</span>" >> "$OUT_HTML"
else
    echo "  <span class=\"gray\">Host status:     </span><span class=\"magenta\">$HOST_STATUS</span>" >> "$OUT_HTML"
fi

echo "  <span class=\"gray\">Stability Score: </span><span class=\"gray\">$STABILITY_SCORE/10</span>" >> "$OUT_HTML"
echo "</pre>" >> "$OUT_HTML"
echo "</body>" >> "$OUT_HTML"
echo "</html>" >> "$OUT_HTML"

echo -e "${GRAY}HTML report saved as: $OUT_HTML${NC}"

# =============================================================================
# ASK TO OPEN BROWSER
# =============================================================================
echo ""
echo -n "Open HTML report in browser? (y/n): "
read browser_answer
if [ "$browser_answer" = "y" ] || [ "$browser_answer" = "Y" ]; then
    open "$OUT_HTML" 2>/dev/null || echo "Could not open browser. File saved at: $OUT_HTML"
fi

# =============================================================================
# EXIT
# =============================================================================
echo ""
echo "Press any key to exit..."
read -n 1
exit 0
