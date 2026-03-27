#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] EverCrypt UEFI Bootkit Builder${NC}"
echo "========================================"

# Set EDK2 path
export EDK2_PATH="$HOME/edk2"
export WORKSPACE="$EDK2_PATH"
export PACKAGES_PATH="$EDK2_PATH"
export EDK_TOOLS_PATH="$EDK2_PATH/BaseTools"
export CONF_PATH="$EDK2_PATH/Conf"

# Auto-detect GCC toolchain
echo -e "${YELLOW}[*] Detecting GCC toolchain...${NC}"
GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
echo "GCC version: $GCC_VERSION"

if [ "$GCC_VERSION" -ge 5 ]; then
    export GCC5_BIN=/usr/bin/
    export GCC5_PREFIX=x86_64-linux-gnu-
    export GCC5_IA32_PREFIX=i686-linux-gnu-
    export GCC5_X64_PREFIX=x86_64-linux-gnu-
    export GCC5_AARCH64_PREFIX=aarch64-linux-gnu-
    echo -e "${GREEN}[✓] GCC5 toolchain configured${NC}"
else
    echo -e "${RED}[!] GCC version too old. Need GCC 5+${NC}"
    exit 1
fi

# Check if EDK2 exists
if [ ! -d "$EDK2_PATH" ]; then
    echo -e "${RED}[!] EDK2 not found at $EDK2_PATH${NC}"
    echo "Installing EDK2..."
    
    cd ~
    git clone --depth=1 https://github.com/tianocore/edk2.git
    cd edk2
    git submodule update --init
fi

cd $EDK2_PATH

# Source the setup script properly
echo -e "${YELLOW}[*] Setting up EDK2 environment...${NC}"
if [ -f "edksetup.sh" ]; then
    source edksetup.sh BaseTools
else
    echo -e "${RED}[!] edksetup.sh not found${NC}"
    exit 1
fi

# Verify environment
echo "WORKSPACE=$WORKSPACE"
echo "EDK_TOOLS_PATH=$EDK_TOOLS_PATH"
echo "CONF_PATH=$CONF_PATH"
echo "GCC5_BIN=$GCC5_BIN"

# Build BaseTools if needed
if [ ! -f "$EDK_TOOLS_PATH/Source/C/bin/GenFv" ]; then
    echo -e "${YELLOW}[*] Building BaseTools...${NC}"
    make -C BaseTools
fi

# Create/update target.txt
mkdir -p $CONF_PATH
cat > $CONF_PATH/target.txt << EOF
ACTIVE_PLATFORM       = MdeModulePkg/MdeModulePkg.dsc
TARGET                = RELEASE
TARGET_ARCH           = X64
TOOL_CHAIN_CONF       = Conf/tools_def.txt
TOOL_CHAIN_TAG        = GCC5
BUILD_RULE_CONF       = Conf/build_rule.txt
MAX_CONCURRENT_THREAD_NUMBER = 4
EOF

# Copy default tools_def if missing
if [ ! -f "$CONF_PATH/tools_def.txt" ]; then
    cp $EDK2_PATH/BaseTools/Conf/tools_def.template $CONF_PATH/tools_def.txt
fi

# Copy default build_rule if missing
if [ ! -f "$CONF_PATH/build_rule.txt" ]; then
    cp $EDK2_PATH/BaseTools/Conf/build_rule.template $CONF_PATH/build_rule.txt
fi

# Copy EverCrypt modules
echo -e "${YELLOW}[*] Copying EverCrypt modules...${NC}"
rm -rf EverCryptPkg
mkdir -p EverCryptPkg/DxeDriver EverCryptPkg/SmmHandler EverCryptPkg/Include
cp -r ~/EverCrypt-Bootkit/uefi_bootkit/* EverCryptPkg/

# Assemble NASM crypto
echo -e "${YELLOW}[*] Assembling SMM crypto (NASM)...${NC}"
nasm -f elf64 "EverCryptPkg/SmmHandler/smm_crypto.nasm" \
     -o "EverCryptPkg/SmmHandler/smm_crypto.obj"

if [ ! -f "EverCryptPkg/SmmHandler/smm_crypto.obj" ]; then
    echo -e "${RED}[!] NASM assembly failed${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Assembly successful${NC}"

# Build DXE Driver
echo -e "${YELLOW}[*] Building EverCryptDxe.efi...${NC}"
build -p MdeModulePkg/MdeModulePkg.dsc \
      -m EverCryptPkg/DxeDriver/EverCryptDxe.inf \
      -a X64 -t GCC5 -b RELEASE || {
    echo -e "${YELLOW}[!] DXE build failed, trying DEBUG build...${NC}"
    build -p MdeModulePkg/MdeModulePkg.dsc \
          -m EverCryptPkg/DxeDriver/EverCryptDxe.inf \
          -a X64 -t GCC5 -b DEBUG
}

# Build SMM Handler
echo -e "${YELLOW}[*] Building EverCryptSmm.efi...${NC}"
build -p MdeModulePkg/MdeModulePkg.dsc \
      -m EverCryptPkg/SmmHandler/EverCryptSmm.inf \
      -a X64 -t GCC5 -b RELEASE || {
    echo -e "${YELLOW}[!] SMM build failed, trying DEBUG build...${NC}"
    build -p MdeModulePkg/MdeModulePkg.dsc \
          -m EverCryptPkg/SmmHandler/EverCryptSmm.inf \
          -a X64 -t GCC5 -b DEBUG
}

# Create output directory
mkdir -p ~/EverCrypt-Bootkit/uefi_bootkit/build/output

# Find and copy built files
echo -e "${YELLOW}[*] Locating built EFI files...${NC}"

find "$EDK2_PATH/Build" -name "EverCryptDxe.efi" -exec cp {} ~/EverCrypt-Bootkit/uefi_bootkit/build/output/ \;
find "$EDK2_PATH/Build" -name "EverCryptSmm.efi" -exec cp {} ~/EverCrypt-Bootkit/uefi_bootkit/build/output/ \;

# List outputs
echo ""
if [ -f ~/EverCrypt-Bootkit/uefi_bootkit/build/output/EverCryptDxe.efi ]; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        UEFI BOOTKIT BUILD SUCCESSFUL                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Outputs:"
    ls -lh ~/EverCrypt-Bootkit/uefi_bootkit/build/output/
else
    echo -e "${YELLOW}[!] Build completed but EFI files not found${NC}"
    echo "Searching in Build directory..."
    find "$EDK2_PATH/Build" -name "*.efi" | grep -i evercrypt
fi

echo ""
echo -e "${YELLOW}[*] Build logs available in: $EDK2_PATH/Build${NC}"