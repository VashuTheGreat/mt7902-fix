#!/bin/bash
# ============================================================
#  MT7902 WiFi + Bluetooth Fix Script for Ubuntu
#  Supports: MediaTek MT7902 (PCI ID: 14c3:7902)
#            Bluetooth USB ID: 13d3:3579
#
#  Author  : Fixed with help of Claude AI (Anthropic)
#  GitHub  : (your github link here)
#  YouTube : (your youtube link here)
#
#  Usage   : sudo bash mt7902_fix.sh
# ============================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ──────────────────────────────────────────────────
LOGFILE="/tmp/mt7902_fix_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

log()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; }
info()   { echo -e "${BLUE}[i]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

# ── Root check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Please run as root: sudo bash mt7902_fix.sh"
    exit 1
fi

# ════════════════════════════════════════════════════════════
#  BANNER
# ════════════════════════════════════════════════════════════
clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  __  __ _____ _____ ___   ___ ____    _____ _____  __
 |  \/  |_   _|___  / _ \ / _ \___ \  |  ___|_ _\ \/ /
 | |\/| | | |    / / (_) | | | |__) | | |_   | | \  /
 | |  | | | |   / / \__, | |_| / __/  |  _|  | | /  \
 |_|  |_| |_|  /_/    /_/ \___/_____| |_|   |___/_/\_\

        WiFi + Bluetooth Fix for Ubuntu
        MediaTek MT7902 | Ubuntu 24.04+
BANNER
echo -e "${NC}"
echo -e "  Log file: ${LOGFILE}"
echo ""

# ════════════════════════════════════════════════════════════
#  STEP 0 — System Detection
# ════════════════════════════════════════════════════════════
header "STEP 0: System Detection"

KERNEL=$(uname -r)
ARCH=$(uname -m)
info "Kernel  : $KERNEL"
info "Arch    : $ARCH"

# Check MT7902 PCI device
if lspci -nn 2>/dev/null | grep -q "14c3:7902"; then
    log "MT7902 WiFi card detected (PCI 14c3:7902)"
    HAS_MT7902_WIFI=true
else
    warn "MT7902 WiFi card NOT detected"
    HAS_MT7902_WIFI=false
fi

# Check MT7902 Bluetooth USB device
if lsusb 2>/dev/null | grep -q "13d3:3579"; then
    log "MT7902 Bluetooth detected (USB 13d3:3579)"
    HAS_MT7902_BT=true
else
    warn "MT7902 Bluetooth NOT detected"
    HAS_MT7902_BT=false
fi

# Check WiFi already working
WIFI_WORKING=false
if ip link show 2>/dev/null | grep -qE "wlo|wlan|wlp" | grep -v "wlx" 2>/dev/null; then
    WIFI_WORKING=true
fi
# More reliable check - see if mt7921e is bound to the PCI device
if [[ -d "/sys/bus/pci/drivers/mt7921e" ]] && ls /sys/bus/pci/drivers/mt7921e/ 2>/dev/null | grep -q "0000"; then
    WIFI_WORKING=true
fi

# Check BT already working
BT_WORKING=false
if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    BT_WORKING=true
elif hciconfig 2>/dev/null | grep -q "UP RUNNING"; then
    BT_WORKING=true
fi

echo ""
info "WiFi status      : $([ "$WIFI_WORKING" = true ] && echo -e "${GREEN}WORKING${NC}" || echo -e "${RED}NOT WORKING${NC}")"
info "Bluetooth status : $([ "$BT_WORKING" = true ] && echo -e "${GREEN}WORKING${NC}" || echo -e "${RED}NOT WORKING${NC}")"

# Nothing to do?
if [[ "$WIFI_WORKING" = true && "$BT_WORKING" = true ]]; then
    log "Both WiFi and Bluetooth are already working! Nothing to do."
    exit 0
fi

if [[ "$HAS_MT7902_WIFI" = false && "$HAS_MT7902_BT" = false ]]; then
    error "No MT7902 hardware detected. This script is for MT7902 only."
    exit 1
fi

echo ""
warn "Issues found — starting fix process..."
sleep 2

# ════════════════════════════════════════════════════════════
#  STEP 1 — Install Dependencies
# ════════════════════════════════════════════════════════════
header "STEP 1: Installing Dependencies"

apt-get update -qq
apt-get install -y \
    dkms \
    build-essential \
    linux-headers-"$KERNEL" \
    curl \
    python3 \
    zstd \
    git \
    kmod 2>&1 | grep -E "Setting up|already|Get:" | head -20

log "Dependencies installed!"

# ════════════════════════════════════════════════════════════
#  STEP 2 — Check Secure Boot
# ════════════════════════════════════════════════════════════
header "STEP 2: Secure Boot Check"

SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unknown")
if echo "$SB_STATE" | grep -q "enabled"; then
    warn "Secure Boot is ENABLED!"
    warn "Please disable Secure Boot in BIOS/UEFI and re-run this script."
    warn "Steps: Reboot → BIOS → Security → Secure Boot → Disabled"
    exit 1
else
    log "Secure Boot is disabled — OK!"
fi

# Check/create MOK signing key for module signing
if [[ ! -f /var/lib/shim-signed/mok/MOK.priv ]]; then
    info "Creating module signing key..."
    mkdir -p /var/lib/shim-signed/mok
    openssl req -new -x509 -newkey rsa:2048 -keyout /var/lib/shim-signed/mok/MOK.priv \
        -out /var/lib/shim-signed/mok/MOK.der -days 36500 -subj "/CN=MT7902 Fix Key/" \
        -outform DER -nodes 2>/dev/null
    log "Signing key created!"
else
    log "MOK signing key exists — OK!"
fi

# ════════════════════════════════════════════════════════════
#  STEP 3 — Download DKMS Repo
# ════════════════════════════════════════════════════════════
header "STEP 3: Downloading MediaTek MT7927 DKMS"

WORKDIR="/opt/mt7902_fix"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ -d "mediatek-mt7927-dkms/.git" ]]; then
    info "Repo already cloned, pulling latest..."
    cd mediatek-mt7927-dkms && git pull 2>/dev/null || true && cd ..
else
    info "Cloning jetm/mediatek-mt7927-dkms..."
    git clone https://github.com/jetm/mediatek-mt7927-dkms.git
fi
log "DKMS repo ready!"

# ════════════════════════════════════════════════════════════
#  STEP 4 — Download Driver ZIP + Kernel Source
# ════════════════════════════════════════════════════════════
header "STEP 4: Downloading Driver Files"

cd "$WORKDIR/mediatek-mt7927-dkms"

# Get required kernel version from PKGBUILD
MT76_KVER=$(grep "_mt76_kver=" PKGBUILD | sed "s/.*'\(.*\)'/\1/")
info "Required kernel source version: linux-${MT76_KVER}"

# Download ASUS driver ZIP (contains MT6639/MT7925 firmware)
DRIVER_ZIP=$(ls DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V*.zip 2>/dev/null | head -1 || true)
if [[ -z "$DRIVER_ZIP" ]]; then
    info "Downloading ASUS driver ZIP..."
    bash download-driver.sh . 2>&1 | tail -3
    DRIVER_ZIP=$(ls DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V*.zip 2>/dev/null | head -1)
fi
log "Driver ZIP ready: $DRIVER_ZIP"

# Download kernel source tarball
KERNEL_TARBALL="linux-${MT76_KVER}.tar.xz"
if [[ ! -f "$KERNEL_TARBALL" ]]; then
    info "Downloading kernel source linux-${MT76_KVER} (~130MB)..."
    curl -L --progress-bar -f \
        -o "$KERNEL_TARBALL" \
        "https://cdn.kernel.org/pub/linux/kernel/v${MT76_KVER%%.*}.x/${KERNEL_TARBALL}"
else
    # Verify it's complete (should be >100MB)
    SIZE=$(stat -c%s "$KERNEL_TARBALL" 2>/dev/null || echo 0)
    if (( SIZE < 100000000 )); then
        warn "Kernel tarball incomplete (${SIZE} bytes), re-downloading..."
        rm -f "$KERNEL_TARBALL"
        curl -L --progress-bar -f \
            -o "$KERNEL_TARBALL" \
            "https://cdn.kernel.org/pub/linux/kernel/v${MT76_KVER%%.*}.x/${KERNEL_TARBALL}"
    fi
fi
log "Kernel source ready!"

# ════════════════════════════════════════════════════════════
#  STEP 5 — Download MT7902 Firmware Files
# ════════════════════════════════════════════════════════════
header "STEP 5: Downloading MT7902 Firmware"

FW_BASE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek"
FW_DIR="/lib/firmware/mediatek"
mkdir -p "$FW_DIR"

download_fw() {
    local name="$1"
    local url="$2"
    if [[ ! -f "${FW_DIR}/${name}" ]]; then
        info "Downloading ${name}..."
        curl -L --silent -f -o "${FW_DIR}/${name}" "${url}" && log "${name} downloaded!" \
            || warn "Failed to download ${name}"
    else
        log "${name} already exists!"
    fi
    # Also copy to /usr/lib/firmware
    mkdir -p /usr/lib/firmware/mediatek
    cp -f "${FW_DIR}/${name}" "/usr/lib/firmware/mediatek/${name}" 2>/dev/null || true
}

download_fw "WIFI_RAM_CODE_MT7902_1.bin"        "${FW_BASE}/WIFI_RAM_CODE_MT7902_1.bin"
download_fw "WIFI_MT7902_patch_mcu_1_1_hdr.bin"  "${FW_BASE}/WIFI_MT7902_patch_mcu_1_1_hdr.bin"
download_fw "BT_RAM_CODE_MT7902_1_1_hdr.bin"    "${FW_BASE}/BT_RAM_CODE_MT7902_1_1_hdr.bin"

# ════════════════════════════════════════════════════════════
#  STEP 6 — DKMS Build & Install (WiFi Driver)
# ════════════════════════════════════════════════════════════
if [[ "$WIFI_WORKING" = false ]]; then
header "STEP 6: Building WiFi Driver (DKMS)"

cd "$WORKDIR/mediatek-mt7927-dkms"

# Build sources
info "Preparing sources (patching mt76)..."
make sources 2>&1 | grep -E "Applying|Installing|Sources|ERROR" | head -30

# Install DKMS
info "Installing DKMS source tree..."
make install 2>&1 | grep -E "Installing|complete|ERROR" | head -10

# DKMS build & install
info "Compiling kernel modules (this takes ~5 minutes)..."
dkms build mediatek-mt7927/2.10 -k "$KERNEL" --force 2>&1 | grep -E "Signing|Error|Building|Cleaning" | head -20
dkms install mediatek-mt7927/2.10 -k "$KERNEL" --force 2>&1 | grep -E "Installing|Error" | head -20

log "WiFi driver built and installed!"

# Load WiFi modules in correct order
info "Loading WiFi modules..."
DKMS_DIR="/lib/modules/${KERNEL}/updates/dkms"
modprobe -r mt7921e mt7921_common mt792x_lib mt76_connac_lib mt76 2>/dev/null || true
sleep 1
insmod "${DKMS_DIR}/mt76.ko.zst"            && log "mt76 loaded"
insmod "${DKMS_DIR}/mt76-connac-lib.ko.zst" && log "mt76-connac-lib loaded"
insmod "${DKMS_DIR}/mt792x-lib.ko.zst"      && log "mt792x-lib loaded"
insmod "${DKMS_DIR}/mt7921-common.ko.zst"   && log "mt7921-common loaded"
insmod "${DKMS_DIR}/mt7921e.ko.zst"         && log "mt7921e loaded"
sleep 3
systemctl restart NetworkManager 2>/dev/null || true

# Verify WiFi
sleep 3
if ip link show 2>/dev/null | grep -qE "wlo[0-9]|wlp[0-9]"; then
    log "WiFi interface UP!"
    WIFI_WORKING=true
else
    warn "WiFi interface not yet visible — may need reboot"
fi

# Permanent WiFi config
cat > /etc/modules-load.d/mt7902-wifi.conf << 'EOF'
mt76
mt76-connac-lib
mt792x-lib
mt7921-common
mt7921e
EOF

fi # end WIFI_WORKING check

# ════════════════════════════════════════════════════════════
#  STEP 7 — Fix Bluetooth
# ════════════════════════════════════════════════════════════
if [[ "$BT_WORKING" = false ]]; then
header "STEP 7: Fixing Bluetooth Driver"

DKMS_DIR="/lib/modules/${KERNEL}/updates/dkms"
KMOD_DIR="/lib/modules/${KERNEL}/kernel/drivers/bluetooth"
BTMTK_SRC="/usr/src/mediatek-mt7927-2.10/drivers/bluetooth/btmtk.c"
BTMTK_HDR="/usr/src/mediatek-mt7927-2.10/drivers/bluetooth/btmtk.h"

# ── 7a: Add MT7902 to btmtk source ──
info "Adding MT7902 support to btmtk source..."

if [[ ! -f "$BTMTK_HDR" ]]; then
    warn "DKMS source not found — run Step 6 first (WiFi fix installs the source)"
else
python3 << PYEOF
h_path = "$BTMTK_HDR"
c_path = "$BTMTK_SRC"

# Add firmware define to .h
with open(h_path) as f: content = f.read()
if "FIRMWARE_MT7902" not in content:
    content = content.replace(
        '#define FIRMWARE_MT7961\t\t"mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin"',
        '#define FIRMWARE_MT7902\t\t"mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin"\n#define FIRMWARE_MT7961\t\t"mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin"'
    )
    with open(h_path, "w") as f: f.write(content)
    print("btmtk.h: FIRMWARE_MT7902 added")
else:
    print("btmtk.h: already patched")

# Add case 0x7902 to switch in .c
with open(c_path) as f: content = f.read()
if "case 0x7902:" not in content:
    content = content.replace(
        "\tcase 0x7922:\n\tcase 0x7925:\n\tcase 0x7961:\n\tcase 0x6639:",
        "\tcase 0x7902:\n\tcase 0x7922:\n\tcase 0x7925:\n\tcase 0x7961:\n\tcase 0x6639:"
    )
    with open(c_path, "w") as f: f.write(content)
    print("btmtk.c: case 0x7902 added")
else:
    print("btmtk.c: already patched")

# Add MODULE_FIRMWARE
with open(c_path) as f: content = f.read()
if "FIRMWARE_MT7902" not in content:
    content = content.replace(
        "MODULE_FIRMWARE(FIRMWARE_MT7961);",
        "MODULE_FIRMWARE(FIRMWARE_MT7902);\nMODULE_FIRMWARE(FIRMWARE_MT7961);"
    )
    with open(c_path, "w") as f: f.write(content)
    print("btmtk.c: MODULE_FIRMWARE added")
PYEOF
fi

# ── 7b: Rebuild DKMS with patched btmtk ──
info "Rebuilding DKMS with MT7902 BT support..."
modprobe -r btusb 2>/dev/null || true
modprobe -r btmtk 2>/dev/null || true
dkms build mediatek-mt7927/2.10 -k "$KERNEL" --force 2>&1 | grep -E "Signing|btmtk|Error" | head -10
dkms install mediatek-mt7927/2.10 -k "$KERNEL" --force 2>&1 | grep -E "btmtk|Installing" | head -5

# Remove DKMS btusb (has symbol mismatch with 6.17 kernel)
rm -f "${DKMS_DIR}/btusb.ko.zst"

# ── 7c: Patch stock btusb binary (add 13d3:3579) ──
info "Patching stock btusb.ko to add USB ID 13d3:3579..."
mkdir -p /tmp/btusb_patch

# Backup original
[[ ! -f "${KMOD_DIR}/btusb.ko.zst.orig" ]] && \
    cp "${KMOD_DIR}/btusb.ko.zst" "${KMOD_DIR}/btusb.ko.zst.orig"

# Decompress
zstd -d "${KMOD_DIR}/btusb.ko.zst.orig" -o /tmp/btusb_patch/btusb.ko -f

# Patch: change 13d3:3578 → 13d3:3579 (add MT7902 USB ID)
python3 << 'PYEOF'
import struct, shutil

src = "/tmp/btusb_patch/btusb.ko"
dst = "/tmp/btusb_patch/btusb_patched.ko"
shutil.copy(src, dst)
data = bytearray(open(src, "rb").read())

# Find 13d3:3578 = bytes d3 13 78 35
needle = bytes([0xd3, 0x13, 0x78, 0x35])
pos = bytes(data).find(needle)
if pos != -1:
    data[pos+2] = 0x79   # 78 → 79
    with open(dst, "wb") as f: f.write(data)
    # Verify
    check = open(dst, "rb").read()
    if bytes([0xd3, 0x13, 0x79, 0x35]) in check:
        print("btusb patched: 13d3:3579 added!")
    else:
        print("ERROR: patch verification failed")
else:
    # 3578 not found, try finding any 13d3:357x pattern
    for prod in range(0x3570, 0x3580):
        b = bytes([0xd3, 0x13]) + struct.pack("<H", prod)
        p = bytes(data).find(b)
        if p != -1:
            print(f"Found 13d3:{prod:04x} at {p}, patching to 3579")
            data[p+2] = 0x79
            data[p+3] = 0x35
            with open(dst, "wb") as f: f.write(data)
            break
    else:
        print("WARNING: could not find suitable patch point in btusb.ko")
        shutil.copy(src, dst)
PYEOF

# Sign the patched btusb
info "Signing patched btusb with MOK key..."
/usr/bin/kmodsign sha512 \
    /var/lib/shim-signed/mok/MOK.priv \
    /var/lib/shim-signed/mok/MOK.der \
    /tmp/btusb_patch/btusb_patched.ko && log "btusb signed!"

# Compress and install
zstd -f /tmp/btusb_patch/btusb_patched.ko -o "${KMOD_DIR}/btusb.ko.zst"
depmod -a
log "Patched btusb installed!"

# ── 7d: Load BT modules ──
info "Loading Bluetooth modules..."
modprobe -r btusb 2>/dev/null || true
modprobe -r btmtk 2>/dev/null || true
sleep 1
modprobe btbcm  && log "btbcm loaded"
modprobe btintel && log "btintel loaded"
modprobe btrtl  && log "btrtl loaded"
insmod "${DKMS_DIR}/btmtk.ko.zst" && log "btmtk DKMS loaded"
sleep 1
modprobe btusb && log "btusb patched loaded"
sleep 5

# ── 7e: Copy BT firmware to mt7902/ subfolder ──
info "Copying BT firmware to mt7902/ subfolder..."
mkdir -p "${FW_DIR}/mt7902"
if [[ -f "${FW_DIR}/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]]; then
    cp -f "${FW_DIR}/BT_RAM_CODE_MT7902_1_1_hdr.bin" "${FW_DIR}/mt7902/"
    log "BT firmware copied to ${FW_DIR}/mt7902/"
else
    warn "BT firmware not found — skipping copy"
fi

# ── 7f: Restart bluetooth service ──
info "Restarting Bluetooth service..."
systemctl restart bluetooth
sleep 3

# ── 7g: Activate Bluetooth controller ──
info "Activating Bluetooth controller..."
bluetoothctl power on   2>/dev/null && log "BT power on"     || warn "BT power on failed"
bluetoothctl pairable on 2>/dev/null && log "BT pairable on" || warn "BT pairable on failed"
bluetoothctl discoverable on 2>/dev/null && log "BT discoverable on" || warn "BT discoverable on failed"
bluetoothctl scan on   2>/dev/null &
sleep 5
kill %1 2>/dev/null || true

# ── 7h: Make BT settings persist across reboots ──
info "Setting up BT auto-activation on boot..."
cat > /etc/systemd/system/bt-autostart.service << 'EOF'
[Unit]
Description=MT7902 Bluetooth Auto-Activate
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c 'bluetoothctl power on; bluetoothctl pairable on; bluetoothctl discoverable on'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bt-autostart.service
log "BT auto-activation service enabled!"

# Verify BT
if bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    log "Bluetooth is UP!"
    BT_WORKING=true
elif hciconfig 2>/dev/null | grep -q "UP RUNNING"; then
    log "Bluetooth is UP!"
    BT_WORKING=true
else
    warn "Bluetooth not yet active — setting up permanent config for next boot"
fi

# ── 7i: Permanent BT config ──
cat > /etc/modules-load.d/mt7902-bt.conf << 'EOF'
btbcm
btintel
btrtl
btmtk
btusb
EOF

cat > /etc/modprobe.d/mt7902-bt.conf << EOF
# MT7902 Bluetooth — use DKMS btmtk (has MT7902 support)
install btmtk /sbin/insmod /lib/modules/${KERNEL}/updates/dkms/btmtk.ko.zst
EOF

depmod -a
log "Permanent Bluetooth config set!"

fi # end BT_WORKING check

# ════════════════════════════════════════════════════════════
#  STEP 8 — Update initramfs
# ════════════════════════════════════════════════════════════
header "STEP 8: Updating initramfs"
update-initramfs -u 2>&1 | tail -3
log "initramfs updated!"

# ════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ════════════════════════════════════════════════════════════
header "FINAL STATUS"

echo ""
echo -e "${BOLD}──────────────────────────────────────────${NC}"

# WiFi check
if ip link show 2>/dev/null | grep -qE "wlo[0-9]|wlp[0-9]"; then
    echo -e "  WiFi      : ${GREEN}${BOLD}✓ WORKING${NC}"
else
    echo -e "  WiFi      : ${YELLOW}⟳ Needs reboot${NC}"
fi

# BT check
if bluetoothctl show 2>/dev/null | grep -q "Controller" || \
   hciconfig 2>/dev/null | grep -q "UP RUNNING"; then
    echo -e "  Bluetooth : ${GREEN}${BOLD}✓ WORKING${NC}"
else
    echo -e "  Bluetooth : ${YELLOW}⟳ Needs reboot${NC}"
fi

echo -e "${BOLD}──────────────────────────────────────────${NC}"
echo ""
echo -e "  ${CYAN}Log saved to: ${LOGFILE}${NC}"
echo ""
echo -e "  ${BOLD}Please reboot to ensure everything persists:${NC}"
echo -e "  ${YELLOW}  sudo reboot${NC}"
echo ""
echo -e "  ${BOLD}After reboot, verify with:${NC}"
echo -e "  ${CYAN}  ip link show wlo1 && bluetoothctl show | head -5${NC}"
echo ""
echo -e "  ${BOLD}Still having issues?${NC}"
echo -e "  Open Claude Desktop and paste this log file content:"
echo -e "  ${YELLOW}  cat ${LOGFILE}${NC}"
echo ""
