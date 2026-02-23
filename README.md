# USB Tree Diagnostic Tool

A simple tool to visualize USB tree structure (tiers, hops, hubs) and assess stability across Windows, macOS, and Linux.

**Target audience**  
- Everyday users who want to quickly check if their USB chain is stable  
- Technicians and sales people who need to share clear, professional diagnostics

## How to Run (one single line)

Paste this command into **PowerShell** (Windows) or **Terminal** (macOS/Linux):

```powershell
irm https://raw.githubusercontent.com/klangche/usb-script/main/Activate-usb-tree.ps1 | iex


The tool will then ask only two questions:

Run with admin/sudo for maximum detail? (y/n)
Open HTML report in browser? (y/n)

Expected Output Examples
With Admin Rights (answer "y" to first question)
Full tree with accurate hops and realistic stability.

USB Diagnostic Tool – Windows priority 1
===========================================
Run with admin/sudo for maximum detail? (y/n): y
→ Admin mode enabled
Platform: Windows 11 Pro (x64)
Host USB Max Tiers: 7 (spec) | Max external hubs: 4 (practical)
Built-in hub: No
Source: Full admin mode
=== USB TREE (from physical port) ===
Root Hub (USB 3.2)
├── Intel USB 3.2 eXtensible Host Controller
│ ├── Anker 7-port Hub (Port 1)
│ │ ├── Logitech Webcam C920 (Port 2) ← 3 hops
│ │ ├── Samsung T7 SSD (Port 3) ← 3 hops
│ │ └── iPad Pro M4 USB-C (Port 4) ← 3 hops (orange for Mac)
│ ├── CalDigit TS4 Dock (Port 5) ← 2 hops
│ │ ├── iPhone 16 Pro USB-C (Port 1) ← 3 hops
│ │ └── Dell 27" Monitor (Port 2) ← 3 hops
│ └── Belkin 10-port Hub (Port 6) ← 2 hops
│ ├── Android Tablet (Samsung) (Port 3) ← 3 hops
│ └── FURTHER HUB → Razer Mouse Dock (Port 4)
│ ├── Razer Mouse (Port 1) ← 4 hops ← ORANGE
│ └── External HDD (Port 2) ← 4 hops ← ORANGE
└── FURTHER HUB → Orico 5-bay Hub (Port 7) ← 3 hops
└── FURTHER HUB → Cheap no-name 4-port (Port 1) ← 4 hops ← ORANGE
└── iPhone 15 USB-C (Port 3) ← 5 hops ← PINK
Furthest jumps from host: 5
Number of tiers: 6
Number of external hubs: 5
Total connected devices: 12
=== STABILITY PER PLATFORM (based on 5 hops) ===
Windows:                  Stable (green – under 5 hops)
Linux:                    Stable (green)
Mac Intel:                Unstable (orange – over 4 hops for Intel)
Mac Apple Silicon:        Not stable (pink – far over 3 hops)
iPad USB-C (M-series):    Unstable (orange)
iPhone USB-C:             Stable (green)
Android Phone (Qualcomm): Stable (green)
Android Tablet (Exynos):  Unstable (orange)
=== SUMMARY FOR THIS HOST ===
Host status for this port: Unstable (orange)
Recommended max for Windows: 4 hops / 3 external hubs
Current: 5 hops / 5 external hubs → OVER LIMIT
If unstable: Reduce number of tiers.
Report saved as: usb-report-20250223-1007.txt
Report saved as: usb-report-20250223-1007.html (opens automatically)

Without Admin Rights
Basic tree based on available information.

USB Tree Diagnostic Tool - Windows mode
Platform: Windows 11 Home
Running with admin: False
Note: Tree is basic. For full detail, use Git Bash or Linux/macOS.
=== USB Tree (basic) ===

USB Root Hub (Ports 10) ← 0 hops
Anker 7-port Hub ← 1 hop
Logitech Webcam ← 2 hops
Samsung T7 SSD ← 2 hops
iPad Pro USB-C ← 2 hops

CalDigit TS4 Dock ← 1 hop
iPhone 16 Pro ← 2 hops



Furthest jumps: 2
Number of tiers: 3
Total devices: 6
=== Stability per platform (based on 2 hops) ===
Windows                  Stable
Linux                    Stable
Mac Intel                Stable
Mac Apple Silicon        Stable
iPad USB-C (M-series)    Stable
iPhone USB-C             Stable
Android Phone (Qualcomm) Stable
Android Tablet (Exynos)  Stable
=== Host summary ===
Host status: Stable
Stability Score: 7/10
If unstable: Reduce number of tiers.
Report saved as C:\Users...\usb-tree-report-20260223-1432.txt
Open HTML report in browser? (y/n)

Supported Platforms



































PlatformWithout adminWith admin/sudoDetail LevelWindows (PowerShell)Basic treeImproved treeGoodLinuxFull tree (lsusb -t)Full + extraExcellentmacOSFull tree (system_profiler)FullExcellentWindows + Git BashFull tree (via bash)FullExcellent
Made to make USB troubleshooting easy for everyone – but detailed enough for professionals.
Questions or improvements? Open an issue!
