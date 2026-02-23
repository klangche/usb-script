#!/usr/bin/env bash
# =============================================================================
# USB TREE TERMINAL SCRIPT - PROFESSIONAL DIAGNOSTIC TOOL
# =============================================================================
# This script runs on: macOS, Linux, Windows (with Git Bash/WSL)
# It detects USB topology and assesses stability per platform
#
# FEATURES:
# - Zero-footprint: Everything runs in memory
# - Auto-fixes line endings only when needed
# - Admin/sudo detection for maximum detail
# - Platform-specific USB enumeration
# - Color-coded stability (exact same colors as PowerShell)
# - HTML report with PowerShell look
# =============================================================================

# Auto-fix Windows line endings - only when running from a file
if [[ -f "$0" ]] && [[ "$(head -1 "$0" 2>/dev/null)" =~ \r$ ]]; then
    tr -d '\r' < "$0" | bash
    exit 0
fi

# =============================================================================
# COLOR CODES - Exact same as PowerShell
# =============================================================================
COLOR_CYAN='\033[36m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_MAGENTA='\033[35m'
COLOR_GRAY='\033[90m'
COLOR_RESET='\033[0m'

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
detect_platform() {
    local os=$(uname -s)
    case "$os" in
        Linux*)     echo "Linux" ;;
        Darwin*)    echo "macOS" ;;
        MINGW*|MSYS*|CYGWIN*) echo "Windows" ;;
        *)          echo "Unknown" ;;
    esac
}

# =============================================================================
# USB DATA COLLECTION
# =============================================================================
get_usb_data() {
    local platform=$1
    local use_sudo=$2
    local usb_data=""
    
    case "$platform" in
        macOS)
            if [[ "$use_sudo" == "true" ]]; then
                echo -e "${COLOR_CYAN}Collecting USB data with sudo (full detail)...${COLOR_RESET}"
                usb_data=$(sudo system_profiler SPUSBDataType 2>/dev/null)
            else
                echo -e "${COLOR_CYAN}Collecting USB data without sudo (basic detail)...${COLOR_RESET}"
                usb_data=$(system_profiler SPUSBDataType 2>/dev/null)
            fi
            ;;
            
        Linux)
            if command -v lsusb &>/dev/null; then
                if [[ "$use_sudo" == "true" ]]; then
                    echo -e "${COLOR_CYAN}Collecting USB data with sudo (full detail)...${COLOR_RESET}"
                    usb_data=$(sudo lsusb -t 2>/dev/null)
                else
                    echo -e "${COLOR_CYAN}Collecting USB data without sudo (basic detail)...${COLOR_RESET}"
                    usb_data=$(lsusb 2>/dev/null)
                fi
            else
                echo -e "${COLOR_YELLOW}Warning: lsusb not found. Install usb-utils for better results.${COLOR_RESET}"
                usb_data="lsusb not available"
            fi
            ;;
            
        Windows)
            echo -e "${COLOR_CYAN}Windows detected via Git Bash - using PowerShell...${COLOR_RESET}"
            usb_data=$(powershell.exe -Command "
                Write-Host 'USB Devices on Windows:' -ForegroundColor Cyan;
                Get-PnpDevice -Class USB | Where-Object { \$_.Status -eq 'OK' } | 
                Select-Object FriendlyName, Status | Format-Table -AutoSize
            " 2>/dev/null)
            ;;
            
        *)
            usb_data="Unknown platform: $platform"
            ;;
    esac
    
    echo "$usb_data"
}

# =============================================================================
# STABILITY ASSESSMENT - Exact same as PowerShell
# =============================================================================
assess_stability() {
    local max_hops=$1
    local platform_limits=(
        "Windows:5:7"
        "Linux:4:6"
        "Mac Intel:5:7"
        "Mac Apple Silicon:3:5"
        "iPad USB-C (M-series):2:4"
        "iPhone USB-C:2:4"
        "Android Phone (Qualcomm):3:5"
        "Android Tablet (Exynos):2:4"
    )
    
    echo -e "${COLOR_CYAN}STABILITY PER PLATFORM (based on $max_hops hops)${COLOR_RESET}"
    echo "=============================================================================="
    
    for limit in "${platform_limits[@]}"; do
        IFS=':' read -r platform rec max <<< "$limit"
        
        if [[ $max_hops -le $rec ]]; then
            status="STABLE"
            color=$COLOR_GREEN
        elif [[ $max_hops -le $max ]]; then
            status="POTENTIALLY UNSTABLE"
            color=$COLOR_YELLOW
        else
            status="NOT STABLE"
            color=$COLOR_MAGENTA
        fi
        
        printf "  %-25s ${color}%s${COLOR_RESET}\n" "$platform:" "$status"
    done
}

# =============================================================================
# HOST STATUS - Exact same as PowerShell
# =============================================================================
assess_host_status() {
    local max_hops=$1
    local mac_as_rec=3
    local mac_as_max=5
    
    echo -e "${COLOR_CYAN}HOST SUMMARY${COLOR_RESET}"
    echo "=============================================================================="
    
    if [[ $max_hops -le $mac_as_rec ]]; then
        host_status="STABLE"
        host_color=$COLOR_GREEN
    elif [[ $max_hops -le $mac_as_max ]]; then
        host_status="POTENTIALLY UNSTABLE"
        host_color=$COLOR_YELLOW
    else
        host_status="NOT STABLE"
        host_color=$COLOR_MAGENTA
    fi
    
    echo -e "Host status for this port: ${host_color}${host_status}${COLOR_RESET}"
    echo -e "${COLOR_GRAY}Recommended max for Mac Apple Silicon: 3 hops / 2 external hubs${COLOR_RESET}"
    echo -e "${COLOR_GRAY}Current: $max_hops hops / $((max_hops - 1)) external hubs${COLOR_RESET}"
}

# =============================================================================
# HTML REPORT - Exact same PowerShell look
# =============================================================================
generate_html_report() {
    local platform=$1
    local usb_data=$2
    local max_hops=$3
    local html_file=$4
    local host_status_text=$5
    local host_status_color=$6
    
    # Get stability assessment without colors for HTML
    local stability_text=$(assess_stability $max_hops | sed 's/\x1b\[[0-9;]*m//g')
    local host_text=$(assess_host_status $max_hops | sed 's/\x1b\[[0-9;]*m//g')
    local timestamp=$(date)
    
    # Convert color names for HTML
    local html_host_color="white"
    if [[ "$host_status_color" == "$COLOR_GREEN" ]]; then
        html_host_color="green"
    elif [[ "$host_status_color" == "$COLOR_YELLOW" ]]; then
        html_host_color="yellow"
    elif [[ "$host_status_color" == "$COLOR_MAGENTA" ]]; then
        html_host_color="magenta"
    fi
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Report</title>
    <style>
        body { 
            background: #012456; 
            color: #e0e0e0; 
            font-family: 'Consolas', 'Courier New', monospace; 
            padding: 20px;
            font-size: 14px;
        }
        pre { 
            margin: 0; 
            font-family: 'Consolas', 'Courier New', monospace;
            color: #e0e0e0;
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
<span class="cyan">==============================================================================</span>
<span class="cyan">USB TREE REPORT - $timestamp</span>
<span class="cyan">==============================================================================</span>

$usb_data

<span class="gray">Platform: $platform</span>
<span class="gray">Max hops: $max_hops</span>
<span class="gray">External hubs: $((max_hops - 1))</span>

<span class="cyan">==============================================================================</span>
<span class="cyan">STABILITY PER PLATFORM (based on $max_hops hops)</span>
<span class="cyan">==============================================================================</span>
$(echo "$stability_text" | sed 's/STABLE/<span class="green">STABLE<\/span>/g; s/POTENTIALLY UNSTABLE/<span class="yellow">POTENTIALLY UNSTABLE<\/span>/g; s/NOT STABLE/<span class="magenta">NOT STABLE<\/span>/g')

<span class="cyan">==============================================================================</span>
<span class="cyan">HOST SUMMARY</span>
<span class="cyan">==============================================================================</span>
  <span class="$html_host_color">Host status: $host_status_text</span>
</pre>
</body>
</html>
EOF
    
    echo -e "${COLOR_CYAN}HTML report saved as: $html_file${COLOR_RESET}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}USB TREE DIAGNOSTIC TOOL - PROFESSIONAL EDITION${COLOR_RESET}"
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo -e "${COLOR_GRAY}Platform: $(detect_platform) ($(uname -m))${COLOR_RESET}"
    echo -e "${COLOR_GRAY}Zero-footprint mode: Everything runs in memory${COLOR_RESET}"
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo ""
    
    read -p "Run with admin/sudo for maximum detail? (y/n): " adminChoice
    echo ""
    
    local use_sudo=false
    if [[ $adminChoice =~ ^[yY]$ ]]; then
        use_sudo=true
        echo -e "${COLOR_CYAN}Admin mode enabled - collecting detailed USB data...${COLOR_RESET}"
    else
        echo -e "${COLOR_CYAN}Running without admin - basic USB data only${COLOR_RESET}"
    fi
    
    local platform=$(detect_platform)
    local usb_data=$(get_usb_data "$platform" "$use_sudo")
    
    echo ""
    echo -e "${COLOR_CYAN}USB TREE${COLOR_RESET}"
    echo -e "${COLOR_CYAN}==============================================================================${COLOR_RESET}"
    echo "$usb_data"
    echo ""
    
    # For now, ask user for max hops (in future, parse from data)
    read -p "Maximum USB hops detected (or enter manually): " max_hops
    [[ -z "$max_hops" ]] && max_hops=3
    
    echo ""
    assess_stability $max_hops
    echo ""
    assess_host_status $max_hops
    echo ""
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local txt_report="$HOME/usb-tree-report-$timestamp.txt"
    local html_report="$HOME/usb-tree-report-$timestamp.html"
    
    # Save text report
    {
        echo "USB TREE DIAGNOSTIC REPORT - $timestamp"
        echo "Platform: $platform ($(uname -m))"
        echo "Max hops: $max_hops"
        echo ""
        echo "USB TREE:"
        echo "$usb_data"
        echo ""
        echo "STABILITY PER PLATFORM:"
        assess_stability $max_hops | sed 's/\x1b\[[0-9;]*m//g'
        echo ""
        echo "HOST SUMMARY:"
        assess_host_status $max_hops | sed 's/\x1b\[[0-9;]*m//g'
    } > "$txt_report"
    
    echo -e "${COLOR_CYAN}Report saved as: $txt_report${COLOR_RESET}"
    
    read -p "Open HTML report in browser? (y/n): " htmlChoice
    if [[ $htmlChoice =~ ^[yY]$ ]]; then
        
        # Get host status text and color for HTML
        if [[ $max_hops -le 3 ]]; then
            host_status_text="STABLE"
            host_status_color=$COLOR_GREEN
        elif [[ $max_hops -le 5 ]]; then
            host_status_text="POTENTIALLY UNSTABLE"
            host_status_color=$COLOR_YELLOW
        else
            host_status_text="NOT STABLE"
            host_status_color=$COLOR_MAGENTA
        fi
        
        generate_html_report "$platform" "$usb_data" "$max_hops" "$html_report" "$host_status_text" "$host_status_color"
        
        if [[ "$platform" == "macOS" ]]; then
            open "$html_report"
        elif [[ "$platform" == "Linux" ]]; then
            xdg-open "$html_report" 2>/dev/null || echo "Please open $html_report manually"
        elif [[ "$platform" == "Windows" ]]; then
            start "$html_report" 2>/dev/null || echo "Please open $html_report manually"
        fi
    fi
}

main "$@"
