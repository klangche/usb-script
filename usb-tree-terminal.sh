#!/usr/bin/env bash
# =============================================================================
# USB TREE TERMINAL SCRIPT - PROFESSIONAL DIAGNOSTIC TOOL
# =============================================================================
# This script runs on: macOS, Linux, Windows (with Git Bash/WSL)
# It detects USB topology and assesses stability per platform
#
# KEY FEATURES:
# - Zero-footprint: Everything runs in memory
# - Auto-fixes line endings only when needed
# - Admin/sudo detection for maximum detail
# - Platform-specific USB enumeration
# - Color-coded stability (orange warning, magenta critical)
# - HTML report generation (optional)
# =============================================================================

# Auto-fix Windows line endings - only when running from a file
if [[ -f "$0" ]] && [[ "$(head -1 "$0" 2>/dev/null)" =~ \r$ ]]; then
    tr -d '\r' < "$0" | bash
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
# USB DATA COLLECTION
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
# STABILITY ASSESSMENT
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
# HOST STATUS
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
    local timestamp=$(date)
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>USB Tree Diagnostic Report</title>
    <style>
        body { font-family: 'Consolas', monospace; background: #0d1117; color: #e6edf3; padding: 30px; }
        h1 { color: #79c0ff; border-bottom: 2px solid #30363d; }
        h2 { color: #79c0ff; margin-top: 30px; }
        pre { background: #161b22; padding: 20px; border-radius: 8px; color: #7ee787; white-space: pre-wrap; }
        .summary { background: #161b22
