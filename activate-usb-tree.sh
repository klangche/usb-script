#!/bin/bash
# =============================================================================
# ACTIVATE USB TREE - macOS/Linux Launcher
# =============================================================================
# This script launches the USB diagnostic tool on macOS and Linux
# It automatically detects the platform and uses the appropriate method
#
# Zero-footprint: Everything runs in memory
# =============================================================================

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

echo -e "${CYAN}==============================================================================${NC}"
echo -e "${CYAN}USB TREE DIAGNOSTIC TOOL - macOS/Linux Launcher${NC}"
echo -e "${CYAN}==============================================================================${NC}"

# Detect platform
OS="$(uname -s)"
case "${OS}" in
    Linux*)     
        PLATFORM="Linux"
        echo -e "${GRAY}Platform: Linux ($(uname -r))${NC}"
        ;;
    Darwin*)    
        PLATFORM="macOS"
        echo -e "${GRAY}Platform: macOS ($(sw_vers -productVersion))${NC}"
        ;;
    *)          
        PLATFORM="Unknown"
        echo -e "${YELLOW}Platform: Unknown (limited support)${NC}"
        ;;
esac

echo -e "${GRAY}Zero-footprint mode: Everything runs in memory${NC}"
echo -e "${CYAN}==============================================================================${NC}"
echo ""

# Download and run the appropriate script
if [ "$PLATFORM" = "macOS" ]; then
    echo -e "${GREEN}Running macOS version...${NC}"
    echo -e "${GRAY}(Script loads directly in memory via pipe, nothing saved)${NC}"
    echo ""
    curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-macos.sh | bash
elif [ "$PLATFORM" = "Linux" ]; then
    echo -e "${GREEN}Running Linux version...${NC}"
    echo -e "${GRAY}(Script loads directly in memory via pipe, nothing saved)${NC}"
    echo ""
    curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-linux.sh | bash
else
    echo -e "${YELLOW}Unknown platform. Attempting to run generic USB scan...${NC}"
    echo ""
    # Try both methods
    if command -v system_profiler &> /dev/null; then
        curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-macos.sh | bash
    elif command -v lsusb &> /dev/null; then
        curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/usb-tree-linux.sh | bash
    else
        echo -e "${YELLOW}No compatible USB tool found.${NC}"
        exit 1
    fi
fi
