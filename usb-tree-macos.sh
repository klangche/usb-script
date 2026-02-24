#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition (FINAL FIX)
# =============================================================================
# Uses system_profiler (works without sudo) and ioreg (with sudo)
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
# ASK FOR ADMIN
# =============================================================================
USE_SUDO="n"
HAS_SUDO=false

if [ "$EUID" -eq 0 ]; then
    HAS_SUDO=true
    echo -e "${GREEN}✓ Running with sudo privileges.${NC}"
else
    echo -n "Run with sudo for maximum detail? (y/n): "
    read USE_SUDO
    if [ "$USE_SUDO" = "y" ] || [ "$USE_SUDO" = "Y" ]; then
        echo -e "${YELLOW}Restarting with sudo...${NC}"
        exec sudo "$0" "$@"
        exit $?
    else
        echo -e "${YELLOW}Running without sudo (using system_profiler).${NC}"
    fi
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

# If we have sudo, use ioreg for detailed tree
if [ "$EUID" -eq 0 ] || [ "$USE_SUDO" = "y" ]; then
    echo -e "${GRAY}Using ioreg for detailed USB tree...${NC}"
    
    # Use ioreg with sudo to get full tree
    ioreg_output=$(ioreg -p IOUSB -r -w 0 -l 2>/dev/null)
    
    # Process ioreg output
    while IFS= read -r line; do
        if [[ "$line" == *"+-o"* ]]; then
            if [[ "$line" =~ \+\-o\ ([^@<]+) ]]; then
                device="${BASH_REMATCH[1]}"
                device=$(echo "$device" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                
                if [ -n "$device" ]; then
                    # Count pipes for level
                    pipes=$(echo "$line" | grep -o "\|" | wc -l)
                    level=$pipes
                    
                    # Build prefix
                    prefix=""
                    for ((i=0; i<level; i++)); do
                        if [ $i -eq $((level-1)) ]; then
                            prefix="${prefix}├── "
                        else
                            prefix="${prefix}│   "
                        fi
                    done
                    
                    # Check if hub
                    if [[ "$device" == *"Hub"* ]] || [[ "$device" == *"HUB"* ]] || [[ "$device" == *"hub"* ]]; then
                        TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} [HUB] ← ${level} hops\n"
                        HUBS=$((HUBS + 1))
                    else
                        TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device} ← ${level} hops\n"
                        DEVICES=$((DEVICES + 1))
                    fi
                    
                    [ $level -gt $MAX_HOPS ] && MAX_HOPS=$level
                fi
            fi
        fi
    done <<< "$ioreg_output"
fi

# If no devices found with ioreg OR we're not using sudo, use system_profiler
if [ -z "$TREE_OUTPUT" ]; then
    echo -e "${GRAY}Using system_profiler for USB tree...${NC}"
    
    # Get USB data from system_profiler
    profiler_output=$(system_profiler SPUSBDataType 2>/dev/null)
    
    # Parse system_profiler output
    level=0
    while IFS= read -r line; do
        # Skip empty lines and property lines
        if [[ -z "$line" ]] || [[ "$line" == *":"*":"* ]] || [[ "$line" == *"Product ID:"* ]] || \
           [[ "$line" == *"Vendor ID:"* ]] || [[ "$line" == *"Speed:"* ]] || \
           [[ "$line" == *"Manufacturer:"* ]] || [[ "$line" == *"Location ID:"* ]] || \
           [[ "$line" == *"Serial Number:"* ]]; then
            continue
        fi
        
        # Count leading spaces to determine level
        indent_count=$(echo "$line" | sed -e 's/^\( *\).*/\1/' | wc -c)
        indent_count=$((indent_count - 1))
        level=$((indent_count / 2))
        
        # Extract device name
        device_name=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/:[[:space:]]*$//')
        
        if [ -n "$device_name" ]; then
            # Build prefix
            prefix=""
            for ((i=0; i<level; i++)); do
                if [ $i -eq $((level-1)) ]; then
                    prefix="${prefix}├── "
                else
                    prefix="${prefix}│   "
                fi
            done
            
            # Check if hub
            if [[ "$device_name" == *"Hub"* ]] || [[ "$device_name" == *"HUB"* ]] || [[ "$device_name" == *"hub"* ]]; then
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device_name} [HUB] ← ${level} hops\n"
                HUBS=$((HUBS + 1))
            else
                TREE_OUTPUT="${TREE_OUTPUT}${prefix}${device_name} ← ${level} hops\n"
                DEVICES=$((DEVICES + 1))
            fi
            
            [ $level -gt $MAX_HOPS ] && MAX_HOPS=$level
        fi
    done <<< "$profiler_output"
fi

# If STILL no devices, show message
if [ -z "$TREE_OUTPUT" ]; then
    TREE_OUTPUT="├── No USB devices detected ← 0 hops\n"
    echo -e "${YELLOW}No USB devices found. Make sure devices are connected.${NC}"
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
# Create HTML file
{
    echo "<!DOCTYPE html>"
    echo "<html>"
    echo "<head>"
    echo "    <title>USB Tree Report</title>"
    echo "    <style>"
    echo "        body { background: #000000; color: #e0e0e0; font-family: 'Consolas', monospace; padding: 20px; font-size: 14px; }"
    echo "        pre { margin: 0; font-family: 'Consolas', monospace; color: #e0e0e0; white-space: pre; }"
    echo "        .cyan { color: #00ffff; }"
    echo "        .green { color: #00ff00; }"
    echo "        .yellow { color: #ffff00; }"
    echo "        .magenta { color: #ff00ff; }"
    echo "        .gray { color: #c0c0c0; }"
    echo "    </style>"
    echo "</head>"
    echo "<body>"
    echo "<pre>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">USB TREE REPORT - $DATE_STAMP</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo ""
    echo -e "$TREE_OUTPUT" | sed 's/\\033\[[0-9;]*m//g'
    echo ""
    echo "<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>"
    echo "<span class=\"gray\">Number of tiers: $NUM_TIERS</span>"
    echo "<span class=\"gray\">Total devices: $DEVICES</span>"
    echo "<span class=\"gray\">Total hubs: $HUBS</span>"
    echo ""
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    
    # Add platform status lines
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if [[ "$line" == *"STABLE"* ]]; then
                echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"green\">STABLE</span>"
            elif [[ "$line" == *"POTENTIALLY UNSTABLE"* ]]; then
                echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"yellow\">POTENTIALLY UNSTABLE</span>"
            elif [[ "$line" == *"NOT STABLE"* ]]; then
                echo "  <span class=\"gray\">$(echo "$line" | cut -c1-25)</span> <span class=\"magenta\">NOT STABLE</span>"
            fi
        fi
    done <<< "$STATUS_SUMMARY"
    
    echo "<span class=\"cyan\">==============================================================================</span>"
    echo "<span class=\"cyan\">HOST SUMMARY</span>"
    echo "<span class=\"cyan\">==============================================================================</span>"
    
    if [ "$HOST_STATUS" = "STABLE" ]; then
        echo "  <span class=\"gray\">Host status:     </span><span class=\"green\">$HOST_STATUS</span>"
    elif [ "$HOST_STATUS" = "POTENTIALLY UNSTABLE" ]; then
        echo "  <span class=\"gray\">Host status:     </span><span class=\"yellow\">$HOST_STATUS</span>"
    else
        echo "  <span class=\"gray\">Host status:     </span><span class=\"magenta\">$HOST_STATUS</span>"
    fi
    
    echo "  <span class=\"gray\">Stability Score: </span><span class=\"gray\">$STABILITY_SCORE/10</span>"
    echo "</pre>"
    echo "</body>"
    echo "</html>"
} > "$OUT_HTML"

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
