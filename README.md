

# USB Tree Diagnostic Tool
![Version](https://img.shields.io/badge/version-0.5.6-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

```powershell
irm https://raw.githubusercontent.com/klangche/usb-script/main/activate-usb-tree.ps1 | iex
```
Paste above command into **PowerShell** (Windows) or **Terminal** (macOS/Linux)


A simple tool to visualize USB tree structure (tiers, hops, hubs) and assess stability across Windows, macOS, and Linux.

**Target audience**  
- Everyday users who want to quickly check if their USB chain is stable  
- Technicians and sales people who need to share clear, professional diagnostics

## How to Run (one single line)

```powershell
irm https://raw.githubusercontent.com/klangche/usb-script/main/activate-usb-tree.ps1 | iex
```
Paste above command into **PowerShell** (Windows) or **Terminal** (macOS/Linux)

<h1>USB Tree Diagnostic Tool</h1>

<p>A simple tool to visualize USB tree structure (tiers, hops, hubs) and assess stability across Windows, macOS, and Linux.</p>


<p>The tool asks only two questions:</p>
<ul>
  <li>Run with admin/sudo for maximum detail? (y/n)</li>
  <li>Open HTML report in browser? (y/n)</li>
</ul>

<h2>Expected Output Examples</h2>

<h3>With Admin Rights (answer "y" to first question)</h3>
<p>Full tree with accurate hops and realistic stability.</p>

<div class="terminal">
<pre>
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
│ │ └── iPad Pro M4 USB-C (Port 4) ← 3 hops <span class="unstable">(orange for Mac)</span>
│ ├── CalDigit TS4 Dock (Port 5) ← 2 hops
│ │ ├── iPhone 16 Pro USB-C (Port 1) ← 3 hops
│ │ └── Dell 27" Monitor (Port 2) ← 3 hops
│ └── Belkin 10-port Hub (Port 6) ← 2 hops
│ ├── Android Tablet (Samsung) (Port 3) ← 3 hops
│ └── FURTHER HUB → Razer Mouse Dock (Port 4)
│ ├── Razer Mouse (Port 1) ← 4 hops ← <span class="unstable">ORANGE</span>
│ └── External HDD (Port 2) ← 4 hops ← <span class="unstable">ORANGE</span>
└── FURTHER HUB → Orico 5-bay Hub (Port 7) ← 3 hops
    └── FURTHER HUB → Cheap no-name 4-port (Port 1) ← 4 hops ← <span class="unstable">ORANGE</span>
        └── iPhone 15 USB-C (Port 3) ← 5 hops ← <span class="not-stable">PINK</span>

Furthest jumps from host: 5
Number of tiers: 6
Number of external hubs: 5
Total connected devices: 12

=== STABILITY PER PLATFORM (based on 5 hops) ===
Windows:                  <span class="stable">Stable</span> (green – under 5 hops)
Linux:                    <span class="stable">Stable</span> (green)
Mac Intel:                <span class="unstable">Unstable</span> (orange – over 4 hops for Intel)
Mac Apple Silicon:        <span class="not-stable">Not stable</span> (pink – far over 3 hops)
iPad USB-C (M-series):    <span class="unstable">Unstable</span> (orange)
iPhone USB-C:             <span class="stable">Stable</span> (green)
Android Phone (Qualcomm): <span class="stable">Stable</span> (green)
Android Tablet (Exynos):  <span class="unstable">Unstable</span> (orange)

=== SUMMARY FOR THIS HOST ===
Host status for this port: <span class="unstable">Unstable</span> (orange)
Recommended max for Windows: 4 hops / 3 external hubs
Current: 5 hops / 5 external hubs → OVER LIMIT

If unstable: Reduce number of tiers.

Report saved as: usb-report-20250223-1007.txt
Report saved as: usb-report-20250223-1007.html (opens automatically)
</pre>
</div>

<h3>Without Admin Rights</h3>
<p>Basic tree based on available information.</p>

<div class="terminal">
<pre>
USB Tree Diagnostic Tool - Windows mode
Platform: Windows 11 Home

Running with admin: False
Note: Tree is basic. For full detail, use Git Bash or Linux/macOS.

=== USB Tree (basic) ===
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
Windows                  <span class="stable">Stable</span>
Linux                    <span class="stable">Stable</span>
Mac Intel                <span class="stable">Stable</span>
Mac Apple Silicon        <span class="stable">Stable</span>
iPad USB-C (M-series)    <span class="stable">Stable</span>
iPhone USB-C             <span class="stable">Stable</span>
Android Phone (Qualcomm) <span class="stable">Stable</span>
Android Tablet (Exynos)  <span class="stable">Stable</span>

=== Host summary ===
Host status: <span class="stable">Stable</span>
Stability Score: 7/10
If unstable: Reduce number of tiers.

Report saved as C:\Users\...\usb-tree-report-20260223-1432.txt
Open HTML report in browser? (y/n)
</pre>
</div>

<h2>Supported Platforms</h2>

<table>
  <tr><th>Platform</th><th>Without admin</th><th>With admin/sudo</th><th>Detail Level</th></tr>
  <tr><td>Windows (PowerShell)</td><td>Basic tree</td><td>Improved tree</td><td>Good</td></tr>
  <tr><td>Linux</td><td>Full tree (lsusb -t)</td><td>Full + extra</td><td>Excellent</td></tr>
  <tr><td>macOS</td><td>Full tree (system_profiler)</td><td>Full</td><td>Excellent</td></tr>
  <tr><td>Windows + Git Bash</td><td>Full tree (via bash)</td><td>Full</td><td>Excellent</td></tr>
</table>

<p>Made to make USB troubleshooting easy for everyone – but detailed enough for professionals.</p>

<p>Questions or improvements? <a href="https://github.com/klangche/usb-script/issues">Open an issue</a>.</p>


## How it works

The script queries native OS USB enumeration tools:

- Windows: WMI / PnPDevice
- Linux: lsusb + sysfs
- macOS: system_profiler SPUSBDataType

The output is normalized into a tree structure and optionally exported as HTML.

## Limitations

- Requires administrator privileges on some systems
- Virtual USB devices may not appear
- Performance depends on OS enumeration speed

