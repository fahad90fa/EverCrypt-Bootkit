#!/usr/bin/env python3
"""
EverCrypt ME Payload Injector
Injects ME payload into FIT region
"""

import sys
import struct
from pathlib import Path

FIT_OFFSET = 0x1000  # Standard FIT location in ME region

def inject_me_payload(firmware_path, payload_path, output_path):
    """Inject ME payload into firmware"""
    
    print(f"[*] Loading firmware: {firmware_path}")
    firmware = bytearray(Path(firmware_path).read_bytes())
    
    print(f"[*] Loading payload: {payload_path}")
    payload = Path(payload_path).read_bytes()
    
    print(f"[*] Payload size: {len(payload):,} bytes")
    
    # Find ME region
    from extract_me import parse_flash_descriptor
    descriptor = parse_flash_descriptor(firmware)
    
    inject_offset = descriptor['me_base'] + FIT_OFFSET
    
    print(f"[*] Injecting at offset: 0x{inject_offset:08X}")
    
    if inject_offset + len(payload) > len(firmware):
        raise ValueError("Payload too large!")
    
    # Inject
    firmware[inject_offset:inject_offset+len(payload)] = payload
    
    # Mark as modified
    firmware[inject_offset-16:inject_offset-12] = b'EVER'
    
    # Save
    Path(output_path).write_bytes(firmware)
    
    print(f"[✓] Modified firmware saved: {output_path}")
    print()
    print("⚠️  WARNING: VERIFY IN QEMU BEFORE FLASHING!")
    print("    qemu-system-x86_64 -bios output.bin -serial stdio")

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: inject_payload.py <firmware.bin> <me_payload.bin> <output.bin>")
        sys.exit(1)
    
    inject_me_payload(sys.argv[1], sys.argv[2], sys.argv[3])