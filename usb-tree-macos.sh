#!/bin/bash
# =============================================================================
# USB TREE DIAGNOSTIC TOOL - macOS Edition
# =============================================================================
# Uses system_profiler SPUSBDataType and ioreg for detailed USB tree
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
echo -e "${GRAY}Platform: macOS $(sw_vers -productVersion) ($(uname -m))${NC}"
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

# Get USB tree using system_profiler (always works)
if [ "$EUID" -eq 0 ]; then
    # With sudo: use ioreg for detailed tree with proper hierarchy
    USB_TREE=$(ioreg -p IOUSB -l -w 0 | sed -e '/^[ ]*/s///' -e 's/[ ]*|//g' 2>/dev/null)
else
    # Without sudo: use system_profiler (less detailed but still good)
    USB_TREE=$(system_profiler SPUSBDataType 2>/dev/null | grep -v "Ejectable" | grep -v "Vendor ID" | grep -v "Product ID")
fi

# Parse into tree structure (simplified for macOS)
TREE_OUTPUT=""
MAX_HOPS=0
HUBS=0
DEVICES=0

# Build tree using ioreg or system_profiler output
if [ "$EUID" -eq 0 ]; then
    # Parse ioreg output for better hierarchy
    TREE_OUTPUT=$(ioreg -p IOUSB -r -w 0 | while read line; do
        if [[ $line =~ \| ]]; then
            level=$(( $(echo "$line" | grep -o "|" | wc -l) / 2 ))
            if [[ $line =~ "IOUSBHostDevice" ]] || [[ $line =~ "IOUSBDevice" ]]; then
                name=$(echo "$line" | sed -n 's/.*"USB Product Name" = "\([^"]*\)".*/\1/p')
                if [ -z "$name" ]; then
                    name=$(echo "$line" | sed -n 's/.*"USB Vendor Name" = "\([^"]*\)".*/\1/p')
                fi
                if [ -z "$name" ]; then
                    name="Unknown USB Device"
                fi
                
                # Check if it's a hub
                if [[ $line =~ "AppleUSB20Hub" ]] || [[ $line =~ "AppleUSB30Hub" ]]; then
                    echo "${level}:${name} [HUB]"
                    ((HUBS++))
                else
                    echo "${level}:${name}"
                    ((DEVICES++))
                fi
                
                if [ $level -gt $MAX_HOPS ]; then
                    MAX_HOPS=$level
                fi
            fi
        fi
    done)
    
    # Convert to tree format
    FORMATTED_TREE=""
    while IFS= read -r line; do
        if [[ $line =~ ^([0-9]+):(.*) ]]; then
            level="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            
            # Build tree prefixes
            prefix=""
            for ((i=0; i<level; i++)); do
                if [ $i -eq $((level-1)) ]; then
                    prefix="${prefix}├── "
                else
                    prefix="${prefix}│   "
                fi
            done
            
            FORMATTED_TREE="${FORMATTED_TREE}${prefix}${name} ← ${level} hops\n"
        fi
    done <<< "$TREE_OUTPUT"
    TREE_OUTPUT="$FORMATTED_TREE"
else
    # Simpler tree from system_profiler
    TREE_OUTPUT=$(system_profiler SPUSBDataType 2>/dev/null | awk '
        /^[ ]*[A-Z]/ { indent=0; }
        /^[ ]+\+/ { indent=1; }
        /^[ ]+\|/ { indent=2; }
        /^[ ]+\+/ { if ($0 ~ /Hub/) { print "├── " $0 " [HUB] ← " indent " hops"; hubs++; } else { print "├── " $0 " ← " indent " hops"; devices++; } }
        /^[ ]+\|/ { print "│   " $0 " ← " indent " hops"; devices++; }
        { if (indent > maxHops) maxHops=indent; }
        END { print "MAX:" maxHops " HUBS:" hubs " DEVICES:" devices }
    ')
    MAX_HOPS=$(echo "$TREE_OUTPUT" | grep "MAX:" | cut -d: -f2)
    HUBS=$(echo "$TREE_OUTPUT" | grep "HUBS:" | cut -d: -f2)
    DEVICES=$(echo "$TREE_OUTPUT" | grep "DEVICES:" | cut -d: -f2)
    TREE_OUTPUT=$(echo "$TREE_OUTPUT" | grep -v "MAX:" | grep -v "HUBS:" | grep -v "DEVICES:")
fi

NUM_TIERS=$((MAX_HOPS + 1))
STABILITY_SCORE=$((9 - MAX_HOPS))
if [ $STABILITY_SCORE -lt 1 ]; then STABILITY_SCORE=1; fi

# =============================================================================
# STABILITY ASSESSMENT (identical to Windows version)
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
    STATUS_LINES="${STATUS_LINES}$plat|$status\n"
done < /tmp/platform_status.txt

# Format for terminal
STATUS_SUMMARY=""
while IFS='|' read plat status; do
    printf -v padded "%-25s" "$plat"
    STATUS_SUMMARY="${STATUS_SUMMARY}${padded} ${status}\n"
done < <(echo -e "$STATUS_LINES")

# Determine host status (based on Mac Apple Silicon)
MAC_AS_STATUS=$(echo -e "$STATUS_LINES" | grep "Mac Apple Silicon" | cut -d'|' -f2)
if [ "$MAC_AS_STATUS" = "NOT STABLE" ]; then
    HOST_STATUS="NOT STABLE"
    HOST_COLOR="$MAGENTA"
elif [ "$MAC_AS_STATUS" = "POTENTIALLY UNSTABLE" ]; then
    HOST_STATUS="POTENTIALLY UNSTABLE"
    HOST_COLOR="$YELLOW"
else
    # Check if any other platform is not stable
    if echo -e "$STATUS_LINES" | grep -q "NOT STABLE" | grep -v "Mac Apple Silicon"; then
        HOST_STATUS="NOT STABLE"
        HOST_COLOR="$MAGENTA"
    elif echo -e "$STATUS_LINES" | grep -q "POTENTIALLY UNSTABLE" | grep -v "Mac Apple Silicon"; then
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
    echo "$TREE_OUTPUT"
    echo ""
    echo "Furthest jumps: $MAX_HOPS"
    echo "Number of tiers: $NUM_TIERS"
    echo "Total devices: $DEVICES"
    echo "Total hubs: $HUBS"
    echo ""
    echo "STABILITY SUMMARY"
    echo "$STATUS_SUMMARY"
    echo "HOST STATUS: $HOST_STATUS (Score: $STABILITY_SCORE/10)"
} > "$OUT_TXT"

echo -e "${GRAY}Report saved as: $OUT_TXT${NC}"

# =============================================================================
# HTML REPORT
# =============================================================================
# Build HTML platform lines
PLATFORM_HTML=""
while IFS='|' read plat status; do
    case "$status" in
        "STABLE") color="green" ;;
        "POTENTIALLY UNSTABLE") color="yellow" ;;
        "NOT STABLE") color="magenta" ;;
    esac
    PLATFORM_HTML="${PLATFORM_HTML}  <span class='gray'>$(printf "%-25s" "$plat")</span> <span class='$color'>$status</span>\r\n"
done < <(echo -e "$STATUS_LINES")

HOST_COLOR_HTML=$(echo "$HOST_COLOR" | sed 's/\\033\[0;32m/green/;s/\\033\[1;33m/yellow/;s/\\033\[0;35m/magenta/')

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

$TREE_OUTPUT

<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>
<span class=\"gray\">Number of tiers: $NUM_TIERS</span>
<span class=\"gray\">Total devices: $DEVICES</span>
<span class=\"gray\">Total hubs: $HUBS</span>

<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>
<span class=\"cyan\">==============================================================================</span>
$PLATFORM_HTML<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">HOST SUMMARY</span>
<span class=\"cyan\">==============================================================================</span>
  <span class='gray'>Host status:     </span><span class='$HOST_COLOR_HTML'>$HOST_STATUS</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$STABILITY_SCORE/10</span>
</pre>
</body>
</html>"

echo "$HTML_CONTENT" > "$OUT_HTML"
echo -e "${GRAY}HTML report saved as: $OUT_HTML${NC}"

echo -n "Open HTML report in browser? (y/n): "
read OPEN_HTML
if [ "$OPEN_HTML" = "y" ]; then
    open "$OUT_HTML"
fi

# =============================================================================
# DEEP ANALYTICS (simplified for macOS)
# =============================================================================
if [ "$EUID" -eq 0 ]; then
    echo ""
    echo -n "Run Deep Analytics to monitor USB stability? (y/n): "
    read RUN_DEEP
    
    if [ "$RUN_DEEP" = "y" ]; then
        echo ""
        echo -e "${MAGENTA}==============================================================================${NC}"
        echo -e "${MAGENTA}DEEP ANALYTICS - USB Event Monitoring${NC}"
        echo -e "${MAGENTA}==============================================================================${NC}"
        echo -e "${GRAY}Monitoring USB connections... Press Ctrl+C to stop${NC}"
        echo ""
        
        # Simple monitoring using ioreg notifications
        DEEP_LOG="/tmp/usb-deep-analytics-$DATE_STAMP.log"
        DEEP_HTML="/tmp/usb-deep-analytics-$DATE_STAMP.html"
        
        RANDOM_ERRORS=0
        REHANDSHAKES=0
        IS_STABLE=true
        START_TIME=$(date +%s)
        
        # Get initial device list
        INITIAL_DEVICES=$(ioreg -p IOUSB -r -w 0 | grep "USB Product Name" | awk -F'"' '{print $4}')
        
        echo "[$(date +%H:%M:%S)] [INFO] Deep Analytics started" >> "$DEEP_LOG"
        
        # Monitoring function
        monitor_usb() {
            local PREV_DEVICES="$INITIAL_DEVICES"
            
            while true; do
                ELAPSED=$(( $(date +%s) - START_TIME ))
                ELAPSED_FMT=$(printf "%02d:%02d:%02d" $((ELAPSED/3600)) $(( (ELAPSED%3600)/60 )) $((ELAPSED%60)))
                
                # Get current devices
                CURRENT_DEVICES=$(ioreg -p IOUSB -r -w 0 | grep "USB Product Name" | awk -F'"' '{print $4}')
                
                # Check for disconnections
                while IFS= read -r dev; do
                    if [ -n "$dev" ] && ! echo "$CURRENT_DEVICES" | grep -q "$dev"; then
                        echo "[$(date +%H:%M:%S)] [REHANDSHAKE] Device disconnected: $dev" >> "$DEEP_LOG"
                        ((REHANDSHAKES++))
                        IS_STABLE=false
                    fi
                done <<< "$PREV_DEVICES"
                
                # Check for new connections
                while IFS= read -r dev; do
                    if [ -n "$dev" ] && ! echo "$PREV_DEVICES" | grep -q "$dev"; then
                        echo "[$(date +%H:%M:%S)] [INFO] Device connected: $dev" >> "$DEEP_LOG"
                    fi
                done <<< "$CURRENT_DEVICES"
                
                PREV_DEVICES="$CURRENT_DEVICES"
                
                # Clear and update display
                clear
                STATUS_COLOR=$([ "$IS_STABLE" = true ] && echo "$GREEN" || echo "$MAGENTA")
                STATUS_TEXT=$([ "$IS_STABLE" = true ] && echo "STABLE" || echo "UNSTABLE")
                
                echo -e "${MAGENTA}==============================================================================${NC}"
                echo -e "${MAGENTA}DEEP ANALYTICS - $ELAPSED_FMT elapsed${NC}"
                echo -e "${GRAY}Press Ctrl+C to stop${NC}"
                echo -e "${MAGENTA}==============================================================================${NC}"
                echo ""
                echo -e "STATUS: \c"
                echo -e "${STATUS_COLOR}$STATUS_TEXT${NC}"
                echo ""
                echo -e "RANDOM ERRORS: \c"
                echo -e "$([ $RANDOM_ERRORS -gt 0 ] && echo "$YELLOW" || echo "$GRAY")$(printf "%02d" $RANDOM_ERRORS)${NC}"
                echo -e "RE-HANDSHAKES: \c"
                echo -e "$([ $REHANDSHAKES -gt 0 ] && echo "$YELLOW" || echo "$GRAY")$(printf "%02d" $REHANDSHAKES)${NC}"
                echo ""
                echo -e "${CYAN}RECENT EVENTS:${NC}"
                
                # Show last 10 events
                tail -n 10 "$DEEP_LOG" | while read event; do
                    if [[ $event == *"ERROR"* ]]; then
                        echo -e "  ${MAGENTA}$event${NC}"
                        ((RANDOM_ERRORS++))
                        IS_STABLE=false
                    elif [[ $event == *"REHANDSHAKE"* ]]; then
                        echo -e "  ${YELLOW}$event${NC}"
                    else
                        echo -e "  ${GRAY}$event${NC}"
                    fi
                done
                
                sleep 1
            done
        }
        
        # Trap Ctrl+C
        trap 'finish' INT
        
        finish() {
            ELAPSED_TOTAL=$(( $(date +%s) - START_TIME ))
            ELAPSED_FMT=$(printf "%02d:%02d:%02d" $((ELAPSED_TOTAL/3600)) $(( (ELAPSED_TOTAL%3600)/60 )) $((ELAPSED_TOTAL%60)))
            
            clear
            echo ""
            echo -e "${MAGENTA}==============================================================================${NC}"
            echo -e "${MAGENTA}DEEP ANALYTICS COMPLETE${NC}"
            echo -e "${MAGENTA}==============================================================================${NC}"
            echo -e "${GRAY}Duration: $ELAPSED_FMT${NC}"
            echo -e "Final status: \c"
            echo -e "$([ "$IS_STABLE" = true ] && echo "${GREEN}STABLE${NC}" || echo "${MAGENTA}UNSTABLE${NC}")"
            echo -e "${GRAY}Random errors: $RANDOM_ERRORS${NC}"
            echo -e "${GRAY}Re-handshakes: $REHANDSHAKES${NC}"
            echo ""
            
            # Generate HTML report
            EVENT_HTML=""
            while IFS= read -r event; do
                if [[ $event == *"ERROR"* ]]; then
                    EVENT_HTML="${EVENT_HTML}  <span class='magenta'>$event</span>\r\n"
                elif [[ $event == *"REHANDSHAKE"* ]]; then
                    EVENT_HTML="${EVENT_HTML}  <span class='yellow'>$event</span>\r\n"
                else
                    EVENT_HTML="${EVENT_HTML}  <span class='gray'>$event</span>\r\n"
                fi
            done < "$DEEP_LOG"
            
            DEEP_HTML_CONTENT="<!DOCTYPE html>
<html>
<head>
    <title>USB Deep Analytics Report</title>
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

$TREE_OUTPUT

<span class=\"gray\">Furthest jumps: $MAX_HOPS</span>
<span class=\"gray\">Number of tiers: $NUM_TIERS</span>
<span class=\"gray\">Total devices: $DEVICES</span>
<span class=\"gray\">Total hubs: $HUBS</span>

<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">STABILITY PER PLATFORM (based on $MAX_HOPS hops)</span>
<span class=\"cyan\">==============================================================================</span>
$PLATFORM_HTML<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">HOST SUMMARY</span>
<span class=\"cyan\">==============================================================================</span>
  <span class='gray'>Host status:     </span><span class='$HOST_COLOR_HTML'>$HOST_STATUS</span>
  <span class='gray'>Stability Score: </span><span class='gray'>$STABILITY_SCORE/10</span>

<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">DEEP ANALYTICS - $ELAPSED_FMT elapsed</span>
<span class=\"cyan\">==============================================================================</span>

  <span class='gray'>Final status:     </span><span class='$([ "$IS_STABLE" = true ] && echo "green" || echo "magenta")'>$([ "$IS_STABLE" = true ] && echo "STABLE" || echo "UNSTABLE")</span>
  <span class='gray'>Random errors:    </span><span class='$([ $RANDOM_ERRORS -gt 0 ] && echo "yellow" || echo "gray")'>$RANDOM_ERRORS</span>
  <span class='gray'>Re-handshakes:    </span><span class='$([ $REHANDSHAKES -gt 0 ] && echo "yellow" || echo "gray")'>$REHANDSHAKES</span>

<span class=\"cyan\">==============================================================================</span>
<span class=\"cyan\">EVENT LOG (in chronological order)</span>
<span class=\"cyan\">==============================================================================</span>
$EVENT_HTML</pre>
</body>
</html>"
            
            echo "$DEEP_HTML_CONTENT" > "$DEEP_HTML"
            
            echo -e "${GRAY}Log file: $DEEP_LOG${NC}"
            echo -e "${GRAY}HTML report: $DEEP_HTML${NC}"
            echo ""
            echo -n "Open Deep Analytics HTML report? (y/n): "
            read OPEN_DEEP
            if [ "$OPEN_DEEP" = "y" ]; then
                open "$DEEP_HTML"
            fi
            exit 0
        }
        
        # Start monitoring
        monitor_usb
        
    else
        echo -e "${GRAY}Deep Analytics skipped.${NC}"
        echo ""
        echo -e "${GRAY}Press any key to exit...${NC}"
        read -n 1
    fi
else
    echo ""
    echo -e "${GRAY}Press any key to exit...${NC}"
    read -n 1
fi
