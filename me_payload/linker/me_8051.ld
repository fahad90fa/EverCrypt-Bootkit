/* ===========================================================================
   EverCrypt ME Linker Script
   Target: 8051 architecture (Intel ME 16/17)
   Output: 32 KB binary for FIT table injection
   =========================================================================== */

MEMORY
{
    /* ME ROM - Firmware Interface Table region */
    ME_CODE (rx)   : ORIGIN = 0x00000000, LENGTH = 28K
    
    /* ME SRAM - Runtime scratch space */
    ME_SRAM (rw)   : ORIGIN = 0x2000F000, LENGTH = 4K
    
    /* Signature region (last 512 bytes) */
    SIGNATURE (r)  : ORIGIN = 0x00007E00, LENGTH = 512
}

SECTIONS
{
    /* Reset vector */
    .reset 0x0000 : {
        *(.reset)
    } > ME_CODE

    /* Main code */
    .text : {
        *(.text)
        *(.text.*)
    } > ME_CODE

    /* Read-only data */
    .rodata : ALIGN(4) {
        *(.rodata)
        *(.rodata.*)
    } > ME_CODE

    /* Crypto tables */
    .crypto : ALIGN(256) {
        KEEP(*(.sbox))
        KEEP(*(.crypto_tables))
    } > ME_CODE

    /* Runtime data in SRAM */
    .data : {
        *(.data)
        *(.data.*)
    } > ME_SRAM

    /* BSS (uninitialized) */
    .bss : {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > ME_SRAM

    /* Signature block (always at end) */
    .signature : {
        KEEP(*(.signature))
        . = ALIGN(512);
        /* Fill remaining with 0xFF (erased flash pattern) */
        FILL(0xFF);
        . = ORIGIN(SIGNATURE) + LENGTH(SIGNATURE) - 1;
        BYTE(0xFF)
    } > SIGNATURE
}

/* Stack setup */
PROVIDE(__stack_top = ORIGIN(ME_SRAM) + LENGTH(ME_SRAM));

/* Entry point */
ENTRY(RESET)