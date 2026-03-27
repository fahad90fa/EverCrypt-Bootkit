#!/usr/bin/env python3
"""
EverCrypt Firmware Integrity Checker
Scans for EverCrypt signatures and validates checksums
"""

import sys
import hashlib
from pathlib import Path

EVERCRYPT_SIGNATURES = [
    b'EVERCRYPT-ME-2025',
    b'EverCryptDxe',
    b'EverCryptSmm',
    b'ECRYPT',  # ME marker
]

def verify_firmware(firmware_path):
    """Check firmware for EverCrypt infection"""
    
    print(f"[*] Scanning: {firmware_path}")
    data = Path(firmware_path).read_bytes()
    
    print(f"[*] Size: {len(data):,} bytes")
    print(f"[*] SHA256: {hashlib.sha256(data).hexdigest()}")
    print()
    
    infected = False
    
    for sig in EVERCRYPT_SIGNATURES:
        if sig in data:
            offset = data.find(sig)
            print(f"[!] Found '{sig.decode('utf-8', errors='ignore')}' at offset 0x{offset:08X}")
            infected = True
    
    if infected:
        print()
        print("[!] ⚠️  FIRMWARE IS INFECTED WITH EVERCRYPT!")
    else:
        print("[✓] Firmware appears clean")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: verify_integrity.py <firmware.bin>")
        sys.exit(1)
    
    verify_firmware(sys.argv[1])