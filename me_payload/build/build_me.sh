#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] EverCrypt ME Payload Builder (Pure Assembly)${NC}"
echo "========================================"

echo -e "${YELLOW}[*] Cleaning...${NC}"
rm -f *.rel *.lst *.hlr *.ihx *.map *.mem *.rst *.sym *.bin 2>/dev/null || true
rm -f ../src/*.rel ../src/*.lst ../src/*.sym 2>/dev/null || true

echo -e "${YELLOW}[*] Assembling modules...${NC}"

# Change to src directory for assembly
cd ../src

sdas8051 -plosgff evercrypt_me.s || {
    echo -e "${RED}[!] Assembly failed for evercrypt_me.s${NC}"
    exit 1
}

sdas8051 -plosgff me_hooks.s || {
    echo -e "${RED}[!] Assembly failed for me_hooks.s${NC}"
    exit 1
}

sdas8051 -plosgff me_crypto.s || {
    echo -e "${RED}[!] Assembly failed for me_crypto.s${NC}"
    exit 1
}

# Move .rel files to build directory
mv *.rel ../build/
cd ../build

# Check if .rel files exist
if [ ! -f evercrypt_me.rel ]; then
    echo -e "${RED}[!] evercrypt_me.rel not created${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Assembly successful${NC}"

echo -e "${YELLOW}[*] Linking...${NC}"
sdld -i evercrypt_me.ihx evercrypt_me.rel me_hooks.rel me_crypto.rel

if [ ! -f evercrypt_me.ihx ]; then
    echo -e "${RED}[!] Linking failed${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Converting to binary...${NC}"
objcopy -I ihex -O binary evercrypt_me.ihx evercrypt_me.bin

SIZE=$(stat -c%s evercrypt_me.bin)

echo -e "${YELLOW}[*] Padding to 32 KB...${NC}"
dd if=/dev/zero of=evercrypt_me_padded.bin bs=32768 count=1 2>/dev/null
dd if=evercrypt_me.bin of=evercrypt_me_padded.bin conv=notrunc 2>/dev/null

printf "EVERCRYPT-ME-2025-$(date +%Y%m%d)" | \
    dd of=evercrypt_me_padded.bin bs=1 seek=32750 conv=notrunc 2>/dev/null

CHECKSUM=$(sha256sum evercrypt_me_padded.bin | cut -d' ' -f1 | head -c16)

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   PURE ASSEMBLY BUILD SUCCESSFUL      ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo "Output:      evercrypt_me_padded.bin"
echo "Size:        32768 bytes"
echo "Code:        ${SIZE} bytes ($(( SIZE * 100 / 32768 ))%)"
echo "SHA256:      ${CHECKSUM}"
