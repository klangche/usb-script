# USB Tree Diagnostic Tool

A simple tool to visualize USB tree structure (tiers, hops, hubs) and assess stability across Windows, macOS, and Linux.

**Target audience**  
- Everyday users who just want to quickly see if their USB chain is stable  
- Technicians/sales people who need to share clear, professional info with customers or support

## How to Run (one single line)

Paste the following into **PowerShell** (Windows) or **Terminal** (macOS/Linux):

```powershell
irm https://raw.githubusercontent.com/klangche/usb-scrip/main/Activate-usb-tree.ps1 | iex


The tool will then ask only two questions:

Do you want to run with admin/sudo for maximum detail? (y/n)
Do you want to open the HTML report in your browser? (y/n)


What to Expect – Output Examples
With Admin Rights (answer "y" to first question)
This is what a typical run looks like when elevated privileges are granted:

USB Diagnos Verktyg – Windows priority 1

===========================================

Vill du köra med admin/sudo för maximal detalj? (j/n): j

→ Admin-läge aktiverat



Plattform: Windows 11 Pro (x64)

Host USB Max Tiers: 7 (spec) | Max externa hubs: 4 (praktiskt)

Built-in hub: Nej

Källa: Full admin-läge



=== USB-TRÄD (från fysisk port) ===

Root Hub (USB 3.2)

├── Intel USB 3.2 eXtensible Host Controller

│   ├── Anker 7-port Hub (Port 1)

│   │   ├── Logitech Webcam C920 (Port 2) ← 3 hopp

│   │   ├── Samsung T7 SSD (Port 3) ← 3 hopp

│   │   └── iPad Pro M4 USB-C (Port 4) ← 3 hopp (orange för Mac)

│   ├── CalDigit TS4 Dock (Port 5) ← 2 hopp

│   │   ├── iPhone 16 Pro USB-C (Port 1) ← 3 hopp

│   │   └── Dell 27" Monitor (Port 2) ← 3 hopp

│   └── Belkin 10-port Hub (Port 6) ← 2 hopp

│       ├── Android Tablet (Samsung) (Port 3) ← 3 hopp

│       └── FURTHER HUB → Razer Mouse Dock (Port 4)

│           ├── Razer Mouse (Port 1) ← 4 hopp ← ORANGE

│           └── External HDD (Port 2) ← 4 hopp ← ORANGE

└── FURTHER HUB → Orico 5-bay Hub (Port 7) ← 3 hopp

    └── FURTHER HUB → Cheap no-name 4-port (Port 1)← 4 hopp ← ORANGE

        └── iPhone 15 USB-C (Port 3) ← 5 hopp ← ROSA



Furthest jumps från datorn: 5

Antal tiers: 6

Antal externa hubs: 5

Totalt anslutna enheter: 12



=== STABILITET PER PLATTFORM (baserat på 5 hopp) ===

Windows: Stable (grönt – under 5 hopp)

Linux: Stable (grönt)

Mac Intel: Unstable (orange – över 4 hopp för Intel)

Mac Apple Silicon: Not working (rosa – långt över 3 hopp)

iPad USB-C (M-serien): Unstable (orange)

iPhone USB-C: Stable (grönt)

Android Phone (Qualcomm): Stable (grönt)

Android Tablet (Exynos): Unstable (orange)



=== SAMMANFATTNING FÖR DENNA DATOR ===

Host status for this port: Unstable (orange)

Rekommenderat max för Windows: 4 hopp / 3 externa hubs

Nuvarande: 5 hopp / 5 externa hubs → ÖVER GRÄNSEN



Tips (Windows):

- Koppla ur Orico-huben och den cheap 4-port hubben → går ner till 3 hopp

- Använd bara CalDigit eller Anker-huben direkt på datorn

- iPad och extra HDD på Belkin-huben är OK, men inte längre kedja



Rapport sparad som: usb-rapport-20250223-1007.txt

Rapport sparad som: usb-rapport-20250223-1007.html (öppnas automatiskt)

With admin you get:

More accurate tree structure
Better detection of deep hubs and real hops
More realistic stability score (often lower if chain is long)

Without Admin Rights
Terminal-output (example on Windows without admin)

USB Tree Diagnostic Tool - Windows-läge

Plattform: Windows 11 Home



Körs med admin: False

Notera: Trädet är grundläggande. För full detalj, använd Git Bash eller Linux/macOS.



=== USB Tree (grundläggande) ===

- USB Root Hub (Ports 10) ← 0 hops

  - Anker 7-port Hub ← 1 hop

    - Logitech Webcam ← 2 hops

    - Samsung T7 SSD ← 2 hops

    - iPad Pro USB-C ← 2 hops

  - CalDigit TS4 Dock ← 1 hop

    - iPhone 16 Pro ← 2 hops



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



Rapport sparad som C:\Users\...\usb-tree-report-20260223-1432.txt

Öppna HTML-rapport i webbläsare? (y/n)

Without admin you get:

Basic tree based on registry + PnP info
May miss some deep hubs or show approximate hops
Stability score tends to be more optimistic


Supported Platforms Overview



































PlatformWithout adminWith admin/sudoDetail LevelWindows (PowerShell)Basic treeImproved treeGoodLinuxFull tree (lsusb -t)Full + extraExcellentmacOSFull tree (system_profiler)FullExcellentWindows + Git BashFull tree (via bash)FullExcellent
Made to make USB troubleshooting easy for everyone – but detailed enough for professionals.
Questions or improvements? Open an issue!
