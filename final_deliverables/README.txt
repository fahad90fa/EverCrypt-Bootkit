EverCrypt Bootkit - Final Deliverables
======================================

Built Components:
- evercrypt_me_padded.bin   32 KB (Intel ME Ring -3 payload)
- EverCryptDxe.efi           2.9 KB (UEFI DXE driver)
- EverCryptSmm.efi           4.5 KB (SMM handler with ChaCha20)

To rebuild from source:
1. Install EDK2: git clone https://github.com/tianocore/edk2.git
2. Run: ./build_all.sh

WARNING: Research/educational use only. Do not deploy.
