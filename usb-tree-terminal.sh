#!/usr/bin/env bash
# =============================================================================
# USB TREE TERMINAL SCRIPT - PROFESSIONAL DIAGNOSTIC TOOL
# =============================================================================
# This script runs on: macOS, Linux, Windows (with Git Bash/WSL)
# It detects USB topology and assesses stability per platform
#
# KEY FEATURES:
# - Zero-footprint: Everything runs in memory
# - Auto-fixes line endings if needed
# - Admin/sudo detection for maximum detail
# - Platform-specific USB enumeration
# - Color-coded stability (orange warning, magenta critical)
# - HTML report generation (optional)
#
# COLOR CODES:
# - \033[33m Orange: Warnings, potentially unstable
# - \033[35m Magenta: Critical, not stable
# - \033[32m Green: Stable
# - \033[36m Cyan: Headers and info
# =============================================================================

# Auto-fix Windows line endings if present (runs in memory)
if [[ "$(head -1 <<<"$(cat)" 2>/dev/null)" =~ \r$ ]]; then
    tr -d '\r' | bash
    exit 0
fi

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
# USB DATA COLLECTION - Platform specific
# =============================================================================
get_usb_data() {
    local platform=$1
    local use_sudo=$2
    local usb_data=""

    case "$platform" in
        macOS)
            if [[ "$use_sudo" == "true" ]]; then
                echo -e "\033[36mCollecting USB data with sudo (full detail)...\033[0m"
                usb_data=$(sudo system_profiler SPUSBDataType 2>/dev/null)
            else
                echo -e "\033[36mCollecting USB data without sudo (basic detail)...\033[0m"
                usb_data=$(system_profiler SPUSBDataType 2>/dev/null)
            fi
            ;;

        Linux)
            if command -v lsusb &>/dev/null; then
                if [[ "$use_sudo" == "true" ]]; then
                    echo -e "\033[36mCollecting USB data with sudo (full detail)...\033[0m"
                    usb_data=$(sudo lsusb -t 2>/dev/null)
                else
                    echo -e "\033[36mCollecting USB data without sudo (basic detail)...\033[0m"
                    usb_data=$(lsusb 2>/dev/null)
                fi
            else
                echo -e "\033[33mWarning: lsusb not found. Install usb-utils for better results.\033[0m"
                usb_data="lsusb not available"
            fi
            ;;

        Windows)
            echo -e "\033[36mWindows detected via Git Bash - using PowerShell...\033[0m"
            # Use PowerShell to get USB devices
            usb_data=$(powershell.exe -Command "
                Write-Host 'USB Devices on Windows:' -ForegroundColor Cyan;
                Get-PnpDevice -Class USB | Where-Object { \$_.Status -eq 'OK' } | 
                Select-Object FriendlyName, Status, InstanceId | 
                Format-Table -AutoSize
            " 2>/dev/null)
            ;;

        *)
            usb_data="Unknown platform: $platform"
            ;;
    esac

    echo "$usb_data"
}

# =============================================================================
# STABILITY ASSESSMENT - Based on USB hops and platform limits
# =============================================================================
# USB LIMITS PER PLATFORM:
# - Windows: Max 5 hops / 4 external hubs
# - Linux: Max 4 hops / 3 external hubs
# - Mac Intel: Max 5 hops / 4 external hubs
# - Mac Apple Silicon: Max 3 hops / 2 external hubs
# - iPad M-series: Max 2 hops / 1 external hub
# - iPhone: Max 2 hops / 1 external hub
# - Android: Varies by chipset
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

    echo -e "\033[36mSTABILITY PER PLATFORM (based on $max_hops hops)\033[0m"
    echo "=============================================================================="

    for limit in "${platform_limits[@]}"; do
        IFS=':' read -r platform rec max <<< "$limit"

        if [[ $max_hops -le $rec ]]; then
            status="STABLE"
            color="\033[32m"
        elif [[ $max_hops -le $max ]]; then
            status="POTENTIALLY UNSTABLE"
            color="\033[33m"
        else
            status="NOT STABLE"
            color="\033[35m"
        fi

        printf "  %-25s %b%s\033[0m\n" "$platform:" "$color" "$status"
    done
}

# =============================================================================
# HOST STATUS - Mac Apple Silicon is the bottleneck
# =============================================================================
assess_host_status() {
    local max_hops=$1

    local mac_as_rec=3
    local mac_as_max=5

    echo -e "\033[36mHOST SUMMARY\033[0m"
    echo "=============================================================================="

    if [[ $max_hops -le $mac_as_rec ]]; then
        host_status="STABLE"
        host_color="\033[32m"
    elif [[ $max_hops -le $mac_as_max ]]; then
        host_status="POTENTIALLY UNSTABLE"
        host_color="\033[33m"
    else
        host_status="NOT STABLE"
        host_color="\033[35m"
    fi

    echo -e "Host status for this port: ${host_color}${host_status}\033[0m"
    echo "Recommended max for Mac Apple Silicon: 3 hops / 2 external hubs"
    echo "Current: $max_hops hops / $((max_hops - 1)) external hubs"

    if [[ $max_hops -gt $mac_as_rec ]]; then
        echo -e "\033[33mIf unstable: Reduce number of tiers.\033[0m"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================
main() {
    echo "=============================================================================="
    echo "USB TREE DIAGNOSTIC TOOL - PROFESSIONAL EDITION"
    echo "=============================================================================="
    echo "Platform: $(detect_platform) ($(uname -m))"
    echo "Zero-footprint mode: Everything runs in memory"
    echo "=============================================================================="
    echo ""

    read -p "Run with admin/sudo for maximum detail? (y/n): " adminChoice
    echo ""

    local use_sudo=false
    if [[ $adminChoice =~ ^[yY]$ ]]; then
        use_sudo=true
        echo -e "\033[36mAdmin mode enabled - collecting detailed USB data...\033[0m"
    else
        echo -e "\033[36mRunning without admin - basic USB data only\033[0m"
    fi

    local platform=$(detect_platform)
    local usb_data=$(get_usb_data "$platform" "$use_sudo")

    echo ""
    echo -e "\033[36mUSB TREE\033[0m"
    echo "=============================================================================="
    echo "$usb_data"
    echo ""

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

    echo -e "\033[36mReport saved as: $txt_report\033[0m"

    read -p "Open HTML report in browser? (y/n): " htmlChoice
    if [[ $htmlChoice =~ ^[yY]$ ]]; then
        generate_html_report "$platform" "$usb_data" "$max_hops" "$html_report"
        if [[ "$platform" == "macOS" ]]; then
            open "$html_report"
        elif [[ "$platform" == "Linux" ]]; then
            xdg-open "$html_report" 2>/dev/null || echo "Please open $html_report manually"
        elif [[ "$platform" == "Windows" ]]; then
            start "$html_report" 2>/dev/null || echo "Please open $html_report manually"
        fi
    fi
}

# =============================================================================
# HTML REPORT GENERATION
# =============================================================================
generate_html_report() {
    local platform=$1
    local usb_data=$2
    local max_hops=$3
    local html_file=$4

    local stability_text=$(assess_stability $max_hops | sed 's/\x1b\[[0-9;]*m//g')
    local host_text=$(assess_host_status $max_hops | sed 's/\x1b\[[0-9;]*m//g')

    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Diagnostic Report</title>
    <style>
        body { font-family: 'Consolas', monospace; background: #0d1117; color: #e6edf3; padding: 30px; }
        h1 { color: #79c0ff; border-bottom: 2px solid #30363d; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; color: #7ee787; }
        .summary { background: #161b22; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .stable { color: #7ee787; }
        .warning { color: #ffa657; }
        .critical { color: #ff7b72; }
        .info { color: #79c0ff; }
    </style>
</head>
<body>
    <h1>USB Tree Diagnostic Report</h1>
    <div class="summary">
        <p><span class="info">Generated:</span> $(date)</p>
        <p><span class="info">Platform:</span> $platform ($(uname -m))</p>
        <p><span class="info">Max hops:</span> $max_hops</p>
    </div>
    <h2>USB Device Tree</h2>
    <pre>$usb_data</pre>
    <h2>Stability Assessment</h2>
    <pre>$stability_text</pre>
    <h2>Host Status</h2>
    <pre>$host_text</pre>
</body>
</html>
EOF

    echo -e "\033[36mHTML report saved as: $html_file\033[0m"
}

main "$@"
