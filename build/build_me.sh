#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] EverCrypt ME Payload Builder${NC}"
echo "========================================"

# Clean
echo -e "${YELLOW}[*] Cleaning...${NC}"
rm -f *.rel *.lst *.hlr *.ihx *.map *.mem *.rst *.sym *.bin *.hex *.lk 2>/dev/null || true
rm -f ../src/*.rel ../src/*.lst ../src/*.sym 2>/dev/null || true

# Assemble
echo -e "${YELLOW}[*] Assembling evercrypt_me.s...${NC}"
cd ../src
sdas8051 -plosgff evercrypt_me.s || exit 1

echo -e "${YELLOW}[*] Assembling me_hooks.s...${NC}"
sdas8051 -plosgff me_hooks.s || exit 1

echo -e "${YELLOW}[*] Assembling me_crypto.s...${NC}"
sdas8051 -plosgff me_crypto.s || exit 1

# Move .rel files to build directory
mv *.rel ../build/
cd ../build

# Check files
if [ ! -f evercrypt_me.rel ]; then
    echo -e "${RED}[!] evercrypt_me.rel not found${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Assembly successful${NC}"

# Create linker script file FIRST
echo -e "${YELLOW}[*] Creating linker script...${NC}"
cat > evercrypt_me.lk << 'LINKSCRIPT'
-mjwx
-i evercrypt_me.ihx
-b CSEG=0x0000
-b GSINIT=0x0100
-b GSFINAL=0x0200
evercrypt_me.rel
me_hooks.rel
me_crypto.rel
-e
LINKSCRIPT

# Link using the script file
echo -e "${YELLOW}[*] Linking...${NC}"
sdld -f evercrypt_me.lk

if [ ! -f evercrypt_me.ihx ]; then
    echo -e "${RED}[!] Linking failed${NC}"
    echo "Trying direct linking..."
    
    # Alternative: direct command line linking
    sdld -mjwxi -b CSEG=0x0000 evercrypt_me.ihx evercrypt_me.rel me_hooks.rel me_crypto.rel
    
    if [ ! -f evercrypt_me.ihx ]; then
        echo -e "${RED}[!] Direct linking also failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[✓] Linking successful${NC}"

# Convert to binary
echo -e "${YELLOW}[*] Converting to binary...${NC}"
objcopy -I ihex -O binary evercrypt_me.ihx evercrypt_me.bin

if [ ! -f evercrypt_me.bin ]; then
    echo -e "${RED}[!] Binary conversion failed${NC}"
    exit 1
fi

SIZE=$(stat -c%s evercrypt_me.bin 2>/dev/null || stat -f%z evercrypt_me.bin)
echo -e "${GREEN}[✓] Binary created: ${SIZE} bytes${NC}"

# Pad to 32KB
echo -e "${YELLOW}[*] Padding to 32 KB...${NC}"
dd if=/dev/zero of=evercrypt_me_padded.bin bs=32768 count=1 2>/dev/null
dd if=evercrypt_me.bin of=evercrypt_me_padded.bin conv=notrunc 2>/dev/null

# Add signature at offset 32750
printf "EVERCRYPT-ME-2025-$(date +%Y%m%d)" | \
    dd of=evercrypt_me_padded.bin bs=1 seek=32750 conv=notrunc 2>/dev/null

CHECKSUM=$(sha256sum evercrypt_me_padded.bin | cut -d' ' -f1 | head -c16)
FINAL_SIZE=$(stat -c%s evercrypt_me_padded.bin)

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ME PAYLOAD BUILD SUCCESSFUL                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Output File:    evercrypt_me_padded.bin"
echo "  Final Size:     ${FINAL_SIZE} bytes (32 KB)"
echo "  Code Size:      ${SIZE} bytes ($(( SIZE * 100 / 32768 ))% used)"
echo "  SHA256:         ${CHECKSUM}..."
echo ""
echo -e "${YELLOW}[*] Verification Commands:${NC}"
echo "    hexdump -C evercrypt_me_padded.bin | head -n 30"
echo "    xxd evercrypt_me.bin | head -n 20"
echo ""
echo -e "${GREEN}[✓] Ring -3 Intel ME Payload Ready${NC}"
echo ""