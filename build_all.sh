#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║          EverCrypt Bootkit - Master Builder              ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Set paths
PROJECT_ROOT="$PWD"
EDK2_PATH="$HOME/edk2"
ME_BUILD="$PROJECT_ROOT/me_payload/build"
UEFI_OUTPUT="$PROJECT_ROOT/uefi_bootkit/build/output"

# Clean output
rm -rf "$UEFI_OUTPUT"
mkdir -p "$UEFI_OUTPUT"

echo -e "${YELLOW}[*] Building ME Payload (Ring -3)...${NC}"
cd "$ME_BUILD"
./build_me.sh

if [ ! -f evercrypt_me_padded.bin ]; then
    echo -e "${RED}[!] ME build failed${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] ME Payload: $(stat -c%s evercrypt_me_padded.bin) bytes${NC}"

echo ""
echo -e "${YELLOW}[*] Building UEFI Bootkit (Ring -2)...${NC}"

# Copy modules to EDK2
cd "$EDK2_PATH"
rm -rf EverCryptPkg
cp -r "$PROJECT_ROOT/uefi_bootkit" EverCryptPkg

# Set up environment
source edksetup.sh BaseTools > /dev/null 2>&1
export GCC_BIN=/usr/bin/

# Build
echo -e "${YELLOW}[*] Compiling DXE Driver...${NC}"
build -p EverCryptPkg/EverCryptPkg.dsc -a X64 -t GCC -b DEBUG -q 2>&1 | grep -i "error\|warning" || true

if [ ! -f Build/EverCrypt/DEBUG_GCC/X64/EverCryptDxe.efi ]; then
    echo -e "${RED}[!] DXE build failed${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] DXE Driver: $(stat -c%s Build/EverCrypt/DEBUG_GCC/X64/EverCryptDxe.efi) bytes${NC}"
echo -e "${GREEN}[✓] SMM Handler: $(stat -c%s Build/EverCrypt/DEBUG_GCC/X64/EverCryptSmm.efi) bytes${NC}"

# Copy outputs to project
cp Build/EverCrypt/DEBUG_GCC/X64/EverCryptDxe.efi "$UEFI_OUTPUT/"
cp Build/EverCrypt/DEBUG_GCC/X64/EverCryptSmm.efi "$UEFI_OUTPUT/"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              BUILD SUCCESSFUL                             ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📦 Outputs:"
echo "   ME Payload:  $ME_BUILD/evercrypt_me_padded.bin"
echo "   DXE Driver:  $UEFI_OUTPUT/EverCryptDxe.efi"
echo "   SMM Handler: $UEFI_OUTPUT/EverCryptSmm.efi"
echo ""
echo -e "${YELLOW}Next: Choose your path${NC}"
echo "  A) Crypto upgrade (ChaCha20)"
echo "  B) FIT injection tool"
echo "  C) QEMU testing"
echo ""
