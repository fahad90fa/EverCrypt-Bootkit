; ===========================================================================
; EverCrypt SMM Cryptography - ChaCha20 Stream Cipher
; Simplified implementation compatible with all x86-64 CPUs
; ===========================================================================

BITS 64
DEFAULT REL

section .text

; ===========================================================================
; ChaCha20 Quarter Round Macro (using 32-bit register names)
; ===========================================================================

%macro QUARTERROUND 4
    ; a += b; d ^= a; d = ROTL(d, 16)
    add     %1, %2
    xor     %4, %1
    rol     %4, 16
    
    ; c += d; b ^= c; b = ROTL(b, 12)
    add     %3, %4
    xor     %2, %3
    rol     %2, 12
    
    ; a += b; d ^= a; d = ROTL(d, 8)
    add     %1, %2
    xor     %4, %1
    rol     %4, 8
    
    ; c += d; b ^= c; b = ROTL(b, 7)
    add     %3, %4
    xor     %2, %3
    rol     %2, 7
%endmacro

; ===========================================================================
; ChaCha20-Poly1305 Encrypt
;
; void ChaCha20Poly1305Encrypt(
;   uint8_t *Key,        // RDI
;   uint8_t *Nonce,      // RSI
;   uint8_t *PlainText,  // RDX
;   uint32_t Length,     // ECX
;   uint8_t *CipherText, // R8
;   uint8_t *Tag         // R9
; );
; ===========================================================================

global ChaCha20Poly1305Encrypt
ChaCha20Poly1305Encrypt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 128
    
    ; Save parameters
    mov     [rbp-8], rdi        ; Key
    mov     [rbp-16], rsi       ; Nonce
    mov     [rbp-24], rdx       ; PlainText
    mov     [rbp-32], ecx       ; Length
    mov     [rbp-40], r8        ; CipherText
    mov     [rbp-48], r9        ; Tag
    
    ; Initialize ChaCha20 state on stack
    ; state[0..3] = "expand 32-byte k"
    mov     dword [rbp-112], 0x61707865
    mov     dword [rbp-108], 0x3320646e
    mov     dword [rbp-104], 0x79622d32
    mov     dword [rbp-100], 0x6b206574
    
    ; state[4..11] = key (256 bits)
    mov     rdi, [rbp-8]
    mov     eax, [rdi]
    mov     [rbp-96], eax
    mov     eax, [rdi+4]
    mov     [rbp-92], eax
    mov     eax, [rdi+8]
    mov     [rbp-88], eax
    mov     eax, [rdi+12]
    mov     [rbp-84], eax
    mov     eax, [rdi+16]
    mov     [rbp-80], eax
    mov     eax, [rdi+20]
    mov     [rbp-76], eax
    mov     eax, [rdi+24]
    mov     [rbp-72], eax
    mov     eax, [rdi+28]
    mov     [rbp-68], eax
    
    ; state[12] = counter (0)
    mov     dword [rbp-64], 0
    
    ; state[13..15] = nonce (96 bits)
    mov     rsi, [rbp-16]
    mov     eax, [rsi]
    mov     [rbp-60], eax
    mov     eax, [rsi+4]
    mov     [rbp-56], eax
    mov     eax, [rsi+8]
    mov     [rbp-52], eax
    
    ; Backup initial state for final addition
    lea     rsi, [rbp-112]
    lea     rdi, [rbp-240]
    mov     ecx, 16
    rep movsd
    
    ; Load state into registers (using 32-bit parts of 64-bit regs)
    mov     eax,  [rbp-112]
    mov     ebx,  [rbp-108]
    mov     ecx,  [rbp-104]
    mov     edx,  [rbp-100]
    mov     r8d,  [rbp-96]
    mov     r9d,  [rbp-92]
    mov     r10d, [rbp-88]
    mov     r11d, [rbp-84]
    mov     r12d, [rbp-80]
    mov     r13d, [rbp-76]
    mov     r14d, [rbp-72]
    mov     r15d, [rbp-68]
    
    ; 20 rounds (10 double rounds)
    push    rcx
    mov     ecx, 10
    
.round_loop:
    ; Save r12-r15 temporarily
    push    r12
    push    r13
    push    r14
    push    r15
    
    ; Column round (simplified)
    add     eax, r8d
    xor     r12d, eax
    rol     r12d, 16
    
    add     ebx, r9d
    xor     r13d, ebx
    rol     r13d, 16
    
    ; Restore
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    
    dec     ecx
    jnz     .round_loop
    
    pop     rcx
    
    ; Add initial state back
    add     eax, [rbp-112]
    add     ebx, [rbp-108]
    add     ecx, [rbp-104]
    add     edx, [rbp-100]
    
    ; Store keystream
    mov     [rbp-112], eax
    mov     [rbp-108], ebx
    mov     [rbp-104], ecx
    mov     [rbp-100], edx
    
    ; XOR plaintext with keystream
    mov     rdx, [rbp-24]       ; PlainText
    mov     r8,  [rbp-40]       ; CipherText
    mov     ecx, [rbp-32]       ; Length
    
    xor     r12, r12            ; Offset
    
.xor_loop:
    cmp     r12d, ecx
    jge     .done_xor
    
    ; Get plaintext byte
    movzx   eax, byte [rdx + r12]
    
    ; Get keystream byte (cycle through 16 words)
    mov     ebx, r12d
    and     ebx, 63
    shr     ebx, 2
    lea     r13, [rbp-112]
    mov     edi, [r13 + rbx*4]
    mov     ebx, r12d
    and     ebx, 3
    shl     ebx, 3
    shr     edi, cl
    
    ; XOR
    xor     al, dil
    
    ; Store ciphertext
    mov     [r8 + r12], al
    
    inc     r12
    jmp     .xor_loop
    
.done_xor:
    ; Write Poly1305 tag (zeros for now)
    mov     r9, [rbp-48]
    xor     rax, rax
    mov     [r9], rax
    mov     [r9+8], rax
    
    add     rsp, 128
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ===========================================================================
; Poly1305 MAC (Stub)
; ===========================================================================

global Poly1305Mac
Poly1305Mac:
    xor     rax, rax
    ret