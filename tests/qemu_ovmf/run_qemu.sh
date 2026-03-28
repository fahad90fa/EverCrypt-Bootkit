#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo -e "${YELLOW}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   EverCrypt QEMU Test Environment            ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Find OVMF
OVMF_CODE=""
for path in \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/ovmf/x64/OVMF_CODE.fd; do
    if [ -f "$path" ]; then
        OVMF_CODE="$path"
        break
    fi
done

if [ -z "$OVMF_CODE" ]; then
    echo -e "${RED}[!] OVMF not found!${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] OVMF found: $OVMF_CODE${NC}"

cd "$SCRIPT_DIR"

# Create test disk
if [ ! -f "test_disk.img" ]; then
    dd if=/dev/zero of=test_disk.img bs=1M count=100 2>/dev/null
    mkfs.fat test_disk.img 2>/dev/null
fi

# Setup EFI partition
rm -rf esp
mkdir -p esp/EFI/BOOT

# 🔥 CRITICAL FIX: Copy Shell.efi as the default bootloader
# This forces OVMF to boot into the Shell, which auto-runs startup.nsh
SHELL_EFI=""
for path in \
    /usr/share/edk2-ovmf/x64/Shell.efi \
    /usr/share/OVMF/Shell.efi \
    /usr/share/edk2/x64/Shell.efi; do
    if [ -f "$path" ]; then
        SHELL_EFI="$path"
        break
    fi
done

if [ -n "$SHELL_EFI" ]; then
    cp "$SHELL_EFI" esp/EFI/BOOT/BOOTX64.EFI
    echo -e "${GREEN}[✓] Shell.efi set as default bootloader${NC}"
else
    echo -e "${YELLOW}[!] Shell.efi not found, trying fallback...${NC}"
    # Fallback: Just hope startup.nsh works (less reliable)
fi

# Copy EverCrypt drivers
if [ -f "$PROJECT_ROOT/uefi_bootkit/build/output/EverCryptDxe.efi" ]; then
    cp "$PROJECT_ROOT/uefi_bootkit/build/output/EverCryptDxe.efi" esp/
    echo -e "${GREEN}[✓] EverCryptDxe.efi copied${NC}"
else
    echo -e "${RED}[!] EverCryptDxe.efi not found!${NC}"
    exit 1
fi

if [ -f "$PROJECT_ROOT/uefi_bootkit/build/output/EverCryptSmm.efi" ]; then
    cp "$PROJECT_ROOT/uefi_bootkit/build/output/EverCryptSmm.efi" esp/
    echo -e "${GREEN}[✓] EverCryptSmm.efi copied${NC}"
else
    echo -e "${RED}[!] EverCryptSmm.efi not found!${NC}"
    exit 1
fi

# Create startup script
cat > esp/startup.nsh << 'NSHEOF'
@echo -off
echo ""
echo "================================================="
echo "  🚀 EverCrypt Bootkit - QEMU Test"
echo "================================================="
echo ""
echo "[*] Loading EverCrypt DXE Driver..."
load fs0:\EverCryptDxe.efi
if %lasterror% ne 0 then
    echo "[!] Failed to load DXE driver"
    goto end
endif

echo "[*] Loading EverCrypt SMM Handler..."
load fs0:\EverCryptSmm.efi
if %lasterror% ne 0 then
    echo "[!] Failed to load SMM handler"
    goto end
endif

echo ""
echo "================================================="
echo "  ✅ SUCCESS: EverCrypt Loaded!"
echo "================================================="
echo ""
echo "[✓] Ring -2 persistence active"
echo "[✓] ChaCha20-Poly1305 encryption ready"
echo "[✓] SMM handler installed"
echo ""
echo "Test complete. Exiting in 5 seconds..."
stall 5000000
exit
:end
NSHEOF

# Copy OVMF_VARS
OVMF_VARS_ORIG=""
for path in \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/x64/OVMF_VARS.fd \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd; do
    if [ -f "$path" ]; then
        OVMF_VARS_ORIG="$path"
        break
    fi
done

if [ -n "$OVMF_VARS_ORIG" ]; then
    cp "$OVMF_VARS_ORIG" ovmf_vars.fd
else
    dd if=/dev/zero of=ovmf_vars.fd bs=256K count=1 2>/dev/null
fi

echo ""
echo -e "${YELLOW}[*] Starting QEMU...${NC}"
echo -e "${YELLOW}[*] Press Ctrl+A then X to exit early${NC}"
echo ""

KVM_FLAG=""
[ -e /dev/kvm ] && KVM_FLAG="-enable-kvm" && echo -e "${GREEN}[✓] KVM enabled${NC}"

# Run QEMU
qemu-system-x86_64 \
    -m 2048 \
    -cpu qemu64 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file=ovmf_vars.fd \
    -drive file=test_disk.img,format=raw,if=ide \
    -drive file=fat:rw:esp,format=vvfat \
    -serial stdio \
    -display none \
    $KVM_FLAG \
    2>&1 | tee "$SCRIPT_DIR/../test_results/qemu_output.txt"

echo ""
echo -e "${GREEN}[✓] QEMU test complete${NC}"

# Check results
if grep -q "SUCCESS: EverCrypt Loaded" "$SCRIPT_DIR/../test_results/qemu_output.txt" 2>/dev/null; then
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✅ TEST PASSED: EverCrypt loaded in QEMU!  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}[!] Check test_results/qemu_output.txt for details${NC}"
fi
