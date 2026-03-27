;; ===========================================================================
;; EverCrypt ME Hooks - DXE Patching
;; ===========================================================================

        .module me_hooks
        .optsdcc -mmcs51 --model-small

        .area CSEG (CODE)

;; ===========================================================================
;; PATCH_DXE_RUNTIME
;; ===========================================================================

        .globl _PATCH_DXE_RUNTIME

_PATCH_DXE_RUNTIME::
        ;; Hook SMM Runtime Protocol
        mov     dptr, #0x1020
        mov     a, #0xC3        ; RET opcode
        movx    @dptr, a
        
        ;; Replace with our handler
        inc     dptr
        mov     a, #0x00
        movx    @dptr, a
        inc     dptr
        mov     a, #0x20
        movx    @dptr, a

        ret

;; ===========================================================================
;; PATCH_PEI_PHASE
;; ===========================================================================

        .globl _PATCH_PEI_PHASE

_PATCH_PEI_PHASE::
        ;; Hook PEI memory discovery
        mov     dptr, #0x0100
        mov     a, #0x90        ; NOP
        movx    @dptr, a
        
        ret