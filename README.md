  
# Linus USB Tree Diagnostic Tool
![Version](https://img.shields.io/badge/version-0.5.6-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)



A simple tool to visualize USB tree structure (tiers, hops, hubs) and assess stability across Windows, macOS, and Linux.


Windows:
```powershell
irm https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-windows.ps1 | iex
```

OSX
```Terminal
curl -sSL https://raw.githubusercontent.com/klangche/usb-script/main/lk-usb-tree-lk-usb-tree-osx.sh | bash
```

Linux
```Terminal
curl -sSL https://raw.githubusercontent.com/yourname/usb-script/main/lk-lusb-tree-linux.sh | bash
```
### HOW TO USE THE TOOL
1. Copy and Paste above command into **PowerShell** or **Terminal**
2. Run in admin och basic*
3. view result
4. view result in browser (copy-paste ready)
5. if in admin run deep analytict**


*not supported on all systems<br>
**not available in OSX nor Linux without powershell.

A lightweight USB diagnostics tool to quickly visualize USB tree structure, count hops/tiers, and assess chain stability — especially useful in corporate BYOD meeting rooms and AV setups.

## Why this tool matters in AV environments
In modern conference rooms we often see:
- USB-C docks (Unisynk, HP, Lenovo, Caldicit, Logitech, TiGHT, Hyper, Targus etc..)
- Multiple hubs daisy-chained
- Webcams, speakerphones, touch panels, wireless presentation dongles, external drives
- iPads/iPhones/Android devices brought by users

Long chains frequently cause problems **only on Apple Silicon Macs** (M1/M2/M3/M4), while Windows and Intel Macs usually work fine.  
This tool helps technicians prove:  
→ "The chain has 5 hops → Windows & Intel OK, but Apple Silicon not stable"

**Target audience**  
- Everyday users who needs troubleshooting or sending IT a proper report.
- Technicians and sales people who need to share clear, professional diagnostics
- Diagnistics team
- IT to verify that the system works with system setups
- POC hard-testing.

## Windows version – what it can do
- Shows full hierarchical USB tree with exact hop counts from root
- Marks hubs clearly [HUB]
- Calculates furthest hop distance and total tiers
- Gives per-platform stability verdict (green/orange/pink) with Apple Silicon emphasis
- Produces beautiful black-background HTML report (looks identical to terminal)
- **Deep Analytics mode** (admin only): real-time monitoring of USB connect/disconnect events, re-handshakes, random errors
- Asks smart questions only once: admin? open report?

###Where macOS and Linux versions do NOT support (yet)

No real-time Deep Analytics / event monitoring (macOS would need log stream, Linux journalctl — not implemented)
macOS tree is good but less precise hop counting than Windows registry method
Linux needs usbutils package + sudo for full tree (no auto-elevation like PowerShell)
No automatic "re-launch as admin" on macOS/Linux (manual sudo)

For AV field use we still recommend Windows laptop as primary diagnostic station — most reliable experience.
Questions / feature requests → open issue.

###Sample output
### Example Full Report – Windows Version with Deep Analytics (3-hour run)

This is a realistic example output from a Windows laptop in a typical AV BYOD troubleshooting scenario:

- **Setup**:
  - Windows 11 laptop
  - Unisynk Pro AV Dock
  - 20 m **AOC active optical** USB-C → Poly Studio E60 Camera **(problematic link)**
  - 5 m passive USB-C to B → Yealink SV80 Camera
  - 2 m passive USB-A to B → Yamaha RM-CR Adecia DSP
  - Ethernet adapter via dock

```powershell
==============================================================================
USB TREE DIAGNOSTIC TOOL - WINDOWS EDITION
==============================================================================
Platform: Windows 11 Pro 23H2 (Build 22631.4169)

Run with admin for maximum detail? (y/n): y
→ Admin mode enabled
✓ Running with administrator privileges.

Enumerating USB devices...
Found 12 devices and 6 hubs

==============================================================================
USB TREE
==============================================================================
└── USB Root Hub (USB 3.2) [HUB] ← 0 hops
    ├── Unisynk Pro AV Dock [HUB] ← 1 hop
    │   ├── Poly Studio E60 Camera ← 2 hops   (via 20m AOC USB-C active optical)
    │   ├── Yealink SV80 Conference Camera ← 2 hops   (via 5m passive USB-C to B)
    │   ├── Yamaha RM-CR Adecia DSP ← 2 hops   (via 2m passive USB-A to B)
    │   ├── Realtek USB GbE Family Controller (Ethernet adapter) ← 2 hops
    │   └── Generic USB Hub (internal dock) [HUB] ← 2 hops
    │       └── Built-in dock USB devices (audio/mic passthrough) ← 3 hops
    └── Intel(R) USB 3.2 eXtensible Host Controller [HUB] ← 1 hop
        ├── Integrated Webcam ← 2 hops
        └── Bluetooth Adapter ← 2 hops

Furthest jumps: 3
Number of tiers: 4
Total devices: 12
Total hubs: 6

==============================================================================
STABILITY PER PLATFORM (based on 3 hops)
==============================================================================
Windows                  STABLE
Linux                    STABLE
Mac Intel                STABLE
Mac Apple Silicon        STABLE           ← borderline at 3 hops
iPad USB-C (M-series)    POTENTIALLY UNSTABLE
iPhone USB-C             STABLE
Android Phone (Qualcomm) STABLE
Android Tablet (Exynos)  POTENTIALLY UNSTABLE

==============================================================================
HOST SUMMARY
==============================================================================
Host status:           STABLE
Stability Score:       6/10

Report saved as: C:\Users\AVTech\AppData\Local\Temp\usb-tree-report-20260224-141245.txt
HTML report saved as: C:\Users\AVTech\AppData\Local\Temp\usb-tree-report-20260224-141245.html

Open HTML report in browser? (y/n): y
(HTML opened – black background with colored status indicators)

Run Deep Analytics to monitor USB stability? (y/n): y

==============================================================================
DEEP ANALYTICS - USB Event Monitoring
==============================================================================
Monitoring USB connections... Press Ctrl+C to stop

Duration: 03:02:17

STATUS: UNSTABLE           ← triggered by Poly E60 instability

RANDOM ERRORS:    04
RE-HANDSHAKES:    03

RECENT EVENTS:
  [14:12:45.218] [INFO]          Deep Analytics started
  [14:15:03.447] [REHANDSHAKE]   Device disconnected   Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [14:15:09.112] [INFO]          Device connected      Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [15:28:56.734] [ERROR]         USB device error detected (timeout/enumeration fail)   Poly Studio E60 Camera
  [16:41:22.109] [REHANDSHAKE]   Device disconnected   Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [16:41:28.892] [INFO]          Device connected      Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [17:03:14.561] [ERROR]         USB device error detected (link drop/power glitch)   Poly Studio E60 Camera
  [17:19:47.305] [ERROR]         USB device error detected (timeout/enumeration fail)   Poly Studio E60 Camera
  [17:35:09.778] [REHANDSHAKE]   Device disconnected   Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [17:35:16.423] [INFO]          Device connected      Poly Studio E60 Camera (Unisynk Pro AV Dock → 20m AOC USB-C)
  [17:42:55.190] [ERROR]         USB device error detected (link instability)   Poly Studio E60 Camera

Final status:     UNSTABLE
Random errors:    4
Re-handshakes:    3

Log file:  C:\Users\AVTech\AppData\Local\Temp\usb-deep-analytics-20260224-141245.log
HTML report: C:\Users\AVTech\AppData\Local\Temp\usb-deep-analytics-20260224-141245.html

Open Deep Analytics HTML report? (y/n): y
(HTML opened – full chronological log with color-coded events)
