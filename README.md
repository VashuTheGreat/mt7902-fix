<div align="center">

# 📡 MT7902 WiFi + Bluetooth Fix for Ubuntu / Linux

**A fully automated fix script for MediaTek MT7902 WiFi 7 & Bluetooth on Ubuntu 24.04+**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%2B-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Kernel](https://img.shields.io/badge/Kernel-6.x-0078D4?logo=linux&logoColor=white)](https://kernel.org)
[![MediaTek](https://img.shields.io/badge/Chip-MT7902-00A3E0)](https://www.mediatek.com)
[![DKMS](https://img.shields.io/badge/DKMS-Supported-brightgreen)](https://github.com/dell/dkms)

<br/>

> 🧠 *Reverse engineered, patched, and fixed with AI assistance using Claude Desktop (Anthropic)*

</div>

---

## 🚨 The Problem

If you installed **Ubuntu** or any Linux distro on a laptop with a **MediaTek MT7902 WiFi 7** card, you likely noticed:

- ❌ No WiFi — interface (`wlo1`, `wlp*`) simply doesn't appear
- ❌ No Bluetooth — device not detected at all

**Why?** The MT7902 chip (`PCI ID: 14c3:7902` / `USB BT: 13d3:3579`) is **not registered** in any stock Linux driver. No `mt7921e`, no `btusb`, no `btmtk` — nothing in mainline Linux supports it out-of-the-box.

This project provides a **100% automated script** that detects, patches, compiles, and loads the correct drivers — fixing both WiFi and Bluetooth in one shot.

---

## ✅ Compatibility

| Component     | Device ID     | Status     |
|---------------|---------------|------------|
| WiFi          | `14c3:7902`   | ✅ Fixed   |
| Bluetooth     | `13d3:3579`   | ✅ Fixed   |
| Ubuntu 24.04+ | Kernel 6.x    | ✅ Tested  |
| ASUS Laptops  | MT7902 WiFi 7 | ✅ Tested  |

---

## ⚠️ IMPORTANT: Disable Secure Boot First!

> **This is mandatory before running the script.**

The fix modifies and loads custom kernel modules. Ubuntu's Secure Boot will **block** unsigned/patched modules.

**Steps to disable Secure Boot:**

1. Reboot your laptop
2. Press `F2` / `DEL` / `ESC` to enter **BIOS/UEFI**
3. Go to **Security** → **Secure Boot**
4. Set it to **Disabled**
5. Save & Exit → Boot back into Ubuntu

> 💡 *The script will automatically check and exit if Secure Boot is still enabled.*

---

## 🎬 Video Tutorials

> 💡 *Agar aap pehle visually samajhna chahte ho — ye videos dekho.*

| # | Video | Description |
|---|-------|-------------|
 1 | ▶️ [**Complete Walkthrough — MT7902 Fix**](https://youtu.be/BtgeDrZrvkk) | Full driver understanding, installation process, and fix explained |
| 2 | ▶️ [**Driver Walkthrough — MT7902 Fix**](https://youtu.be/bjYPuqOtVgI) | Full driver understanding, installation process, and fix explained |
| 3 | ▶️ [**How to Install Claude Desktop on Ubuntu**](https://youtu.be/NqMU9cL2LfE) | Setup Claude Desktop (Debian/Ubuntu) to use AI for driver fixing |

---

## 🚀 Quick Start

```bash
git clone https://github.com/VashuTheGreat/mt7902-fix
cd mt7902-fix
sudo bash mt7902_fix.sh
sudo reboot
```

After reboot, verify with:

```bash
ip link show wlo1
bluetoothctl show | head -5
```

---

## 🔍 How It Works — Full Technical Story

### Step 0 — System Detection
The script auto-detects your hardware:
- Scans `lspci` for `14c3:7902` → MT7902 WiFi
- Scans `lsusb` for `13d3:3579` → MT7902 Bluetooth
- Checks if WiFi/BT are already working
- Skips steps that aren't needed

---

### Step 1 — Root Cause Identified

Running `modinfo mt7925e` revealed that the driver only lists IDs `0717` and `7925`. PCI ID `7902` was **completely missing** from the driver table — meaning Linux couldn't bind any driver to the device.

---

### Step 2 — DKMS Repo Found

We discovered **[jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms)** on GitHub — a community DKMS package that includes `mt7902-wifi-6.19.patch`. This patch adds `14c3:7902` to the `mt7921e` driver's PCI ID table, allowing the driver to bind.

---

### Step 3 — WiFi Fix

The WiFi fix involves a 3-phase process:

```
ASUS CDN Driver ZIP
        ↓
linux-6.19.x kernel source (mt76 driver extracted)
        ↓
mt7902-wifi patch applied → DKMS compile
        ↓
Modules loaded: mt76 → mt76-connac-lib → mt792x-lib → mt7921-common → mt7921e
        ↓
✅  wlo1 interface appears | ASIC revision: 79020000 detected
```

**Modules installed via DKMS** (persistent across kernel updates):
- `mt76.ko`
- `mt76-connac-lib.ko`
- `mt792x-lib.ko`
- `mt7921-common.ko`
- `mt7921e.ko`

**Firmware files downloaded** from `linux-firmware` git:
- `WIFI_RAM_CODE_MT7902_1.bin`
- `WIFI_MT7902_patch_mcu_1_1_hdr.bin`

---

### Step 4 — Bluetooth Problem

The Bluetooth fix was significantly harder. Two separate issues needed solving:

| Problem | Detail |
|---------|--------|
| `btusb.ko` (stock) | USB ID `13d3:3579` not in the device table |
| `btmtk.ko` (stock) | `case 0x7902` missing in firmware dispatch switch |

---

### Step 5 — Bluetooth Fix (3-Part Solution)

#### Part A — Patch `btmtk` Source (DKMS)

Added `case 0x7902:` to the `btmtk.c` switch statement and defined the firmware path:

```c
// In btmtk.h:
#define FIRMWARE_MT7902  "mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin"

// In btmtk.c switch:
case 0x7902:   // ← added
case 0x7922:
case 0x7925:
...
```

Then rebuilt via DKMS to get a new patched `btmtk.ko`.

#### Part B — Binary Patch `btusb.ko`

Since `btusb.ko` is a stock kernel module (not in DKMS), we did a **binary patch**:

```python
# Replaced bytes: 13d3:3578 → 13d3:3579
# (little-endian: d3 13 78 35 → d3 13 79 35)
```

This adds USB ID `13d3:3579` to the stock `btusb` device table without recompiling the entire kernel.

#### Part C — Kernel Module Signing

Ubuntu requires custom kernel modules to be signed when any form of module signature checking is active:

```bash
# Generate MOK key (Machine Owner Key)
openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -out MOK.der ...

# Sign the patched btusb module
kmodsign sha512 MOK.priv MOK.der btusb_patched.ko
```

The signed + compressed module replaces the stock `btusb.ko.zst` in the kernel module path.

#### Correct Load Order (Critical!)

```
btbcm → btintel → btrtl → btmtk (DKMS) → btusb (patched)
```

---

### Step 6 — Persistence

The script sets up permanent configs so everything survives reboots and kernel updates:

```
/etc/modules-load.d/mt7902-wifi.conf  → WiFi modules auto-load
/etc/modules-load.d/mt7902-bt.conf   → BT modules auto-load
/etc/modprobe.d/mt7902-bt.conf       → Routes btmtk to DKMS version
```

`initramfs` is also updated via `update-initramfs -u`.

---

## 📋 What the Script Does — Summary

```
✓ Detects MT7902 WiFi (14c3:7902) and Bluetooth (13d3:3579)
✓ Installs build dependencies (dkms, linux-headers, etc.)
✓ Checks Secure Boot status
✓ Creates MOK signing key
✓ Clones jetm/mediatek-mt7927-dkms
✓ Downloads ASUS driver ZIP + linux-6.19 kernel source
✓ Downloads MT7902 firmware blobs
✓ Builds and installs WiFi driver via DKMS
✓ Patches btmtk.c source → DKMS rebuild
✓ Binary patches btusb.ko (adds USB ID 13d3:3579)
✓ Signs patched module with MOK key
✓ Loads all modules in correct order
✓ Sets up permanent boot config
✓ Updates initramfs
✓ Shows final status report
```

---

## 🛠️ Manual Verification After Reboot

```bash
# Check WiFi
ip link show wlo1
nmcli device status

# Check Bluetooth
bluetoothctl show
hciconfig -a

# Check loaded modules
lsmod | grep mt792
lsmod | grep btmtk
lsmod | grep btusb

# Check PCI binding
ls /sys/bus/pci/drivers/mt7921e/

# Check dmesg for firmware
dmesg | grep -i "mt7902\|79020000\|firmware"
```

---

## 📁 Project Structure

```
mt7902-fix/
├── mt7902_fix.sh     # Main automated fix script
├── README.md         # This file
└── LICENSE           # MIT License
```

---

## 📦 Dependencies (Auto-installed by script)

- `dkms`
- `build-essential`
- `linux-headers-$(uname -r)`
- `curl`, `git`, `python3`, `zstd`, `kmod`

---

## 🤖 How This Was Built

This entire fix — from reverse engineering the problem to writing the patch script — was developed as a **human + AI collaboration**:

- 🔬 Root cause analysis done by examining kernel module device tables
- 🐛 Driver patching strategy developed iteratively through testing
- 🤖 Script written with help from **Claude Desktop** (Anthropic) using filesystem + terminal MCP connectors
- ✅ Tested on ASUS laptop with MediaTek MT7902 WiFi 7 module

> *Proof that complex kernel-level driver issues can be debugged and fixed with modern AI tooling.*

---

## 🧠 Install Claude Desktop on Ubuntu (to replicate this workflow)

Want to use Claude Desktop the same way this fix was built? Install it on Ubuntu/Debian:

📺 **Video Guide:** [How to Install Claude Desktop on Ubuntu](https://youtu.be/NqMU9cL2LfE)

```bash
# Step 1: Add the GPG key
curl -fsSL https://aaddrick.github.io/claude-desktop-debian/KEY.gpg | sudo gpg --dearmor -o /usr/share/keyrings/claude-desktop.gpg

# Step 2: Add the repository
echo "deb [signed-by=/usr/share/keyrings/claude-desktop.gpg arch=amd64,arm64] https://aaddrick.github.io/claude-desktop-debian stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop.list

# Step 3: Update and install
sudo apt update
sudo apt install claude-desktop
```

Once installed, connect **filesystem** and **terminal** MCP connectors in Claude Desktop settings — that's how this entire driver fix was reverse-engineered and scripted with AI assistance.

---

## ⚡ Troubleshooting

| Issue | Solution |
|-------|----------|
| Script exits at Secure Boot check | Disable Secure Boot in BIOS → re-run |
| WiFi not working after reboot | Run `dmesg \| grep mt7902` and check log file |
| Bluetooth not detected | Check `lsusb` for `13d3:3579` first |
| DKMS build fails | Check `linux-headers` are installed for your exact kernel |
| Module not loading | Check `dmesg` for signing errors — MOK key issue |

**Still stuck?** Check the auto-generated log file:
```bash
cat /tmp/mt7902_fix_*.log
```

---

## 🙏 Credits & References

### 📦 Technical Resources
- **[jetm/mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms)** — The community DKMS package with the critical `mt7902` patch
- **[linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)** — Official firmware blobs
- **[kernel.org](https://cdn.kernel.org)** — Linux kernel source
- **[Claude Desktop by Anthropic](https://claude.ai/download)** — AI assistant used for scripting and debugging
- **[claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian)** — Unofficial Claude Desktop package for Debian/Ubuntu

### 🎬 Video References
- ▶️ [MT7902 Driver Fix — Full Walkthrough](https://youtu.be/bjYPuqOtVgI) — Reference video for understanding the driver patching process
- ▶️ [How to Install Claude Desktop on Ubuntu](https://youtu.be/NqMU9cL2LfE) — Setup guide for Claude Desktop on Debian/Ubuntu

---

## 📄 License

```
MIT License — Free to use, modify, and distribute.
See LICENSE file for details.
```

---

<div align="center">

**Made with ❤️ for the Linux community**

*If this fixed your WiFi/Bluetooth — drop a ⭐ on the repo!*

</div>
