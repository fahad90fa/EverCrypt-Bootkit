;;; ===========================================================================
;;; EverCrypt ME Crypto Module
;;; ===========================================================================

        .module me_crypto
        
        .area   CSEG    (CODE)

;;; ===========================================================================
;;; ENCRYPT_BLOCK - Simple encryption
;;; Input: R0 = input, R1 = output
;;; ===========================================================================

        .globl  encrypt_block

encrypt_block:
        mov     r7, #16

enc_loop:
        mov     a, @r0
        xrl     a, #0x63
        xrl     a, r7
        mov     @r1, a
        inc     r0
        inc     r1
        djnz    r7, enc_loop
        ret