/** @file
  ChaCha20-Poly1305 AEAD Cipher
  
  RFC 7539 compliant implementation for UEFI/SMM
  Optimized for no-heap, stack-only execution
**/

#ifndef __EVERCRYPT_CHACHA20_H__
#define __EVERCRYPT_CHACHA20_H__

#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>

#define CHACHA_KEY_SIZE     32
#define CHACHA_NONCE_SIZE   12
#define CHACHA_BLOCK_SIZE   64
#define POLY1305_TAG_SIZE   16

#pragma pack(1)

typedef struct {
  UINT32  State[16];
  UINT32  Counter;
} CHACHA20_CTX;

typedef struct {
  UINT64  R[2];
  UINT64  H[3];
  UINT64  Pad[2];
} POLY1305_CTX;

#pragma pack()

/**
  Initialize ChaCha20 context
  
  @param[out] Ctx         ChaCha20 context
  @param[in]  Key         32-byte key
  @param[in]  Nonce       12-byte nonce
  @param[in]  Counter     Initial counter (usually 0)
**/
VOID
ChaCha20Init (
  OUT CHACHA20_CTX  *Ctx,
  IN  UINT8         *Key,
  IN  UINT8         *Nonce,
  IN  UINT32        Counter
  );

/**
  Encrypt/Decrypt data stream
  
  @param[in,out] Ctx      ChaCha20 context
  @param[in]     Input    Input data
  @param[out]    Output   Output data
  @param[in]     Length   Data length
**/
VOID
ChaCha20Crypt (
  IN OUT CHACHA20_CTX  *Ctx,
  IN     UINT8         *Input,
  OUT    UINT8         *Output,
  IN     UINTN         Length
  );

/**
  Initialize Poly1305 MAC
  
  @param[out] Ctx         Poly1305 context
  @param[in]  Key         32-byte key (derived from ChaCha20)
**/
VOID
Poly1305Init (
  OUT POLY1305_CTX  *Ctx,
  IN  UINT8         *Key
  );

/**
  Update Poly1305 with data
  
  @param[in,out] Ctx      Poly1305 context
  @param[in]     Data     Data to authenticate
  @param[in]     Length   Data length
**/
VOID
Poly1305Update (
  IN OUT POLY1305_CTX  *Ctx,
  IN     UINT8         *Data,
  IN     UINTN         Length
  );

/**
  Finalize Poly1305 and get tag
  
  @param[in,out] Ctx      Poly1305 context
  @param[out]    Tag      16-byte authentication tag
**/
VOID
Poly1305Final (
  IN OUT POLY1305_CTX  *Ctx,
  OUT    UINT8         *Tag
  );

/**
  ChaCha20-Poly1305 AEAD Encrypt
  
  @param[in]  Key         32-byte key
  @param[in]  Nonce       12-byte nonce
  @param[in]  Plaintext   Input plaintext
  @param[in]  Length      Plaintext length
  @param[out] Ciphertext  Output ciphertext
  @param[out] Tag         16-byte authentication tag
**/
VOID
ChaCha20Poly1305Encrypt (
  IN  UINT8  *Key,
  IN  UINT8  *Nonce,
  IN  UINT8  *Plaintext,
  IN  UINTN  Length,
  OUT UINT8  *Ciphertext,
  OUT UINT8  *Tag
  );

#endif // __EVERCRYPT_CHACHA20_H__