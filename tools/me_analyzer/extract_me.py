#!/usr/bin/env python3
"""
EverCrypt ME Region Extractor
Parses Intel Flash Descriptor and extracts ME region
"""

import sys
import struct
from pathlib import Path

def parse_flash_descriptor(firmware_data):
    """Parse Intel Flash Descriptor"""
    
    if len(firmware_data) < 0x1000:
        raise ValueError("Firmware too small")
    
    # Check signature (0x0FF0A55A at offset 0x10)
    sig = struct.unpack('<I', firmware_data[0x10:0x14])[0]
    if sig != 0x0FF0A55A:
        raise ValueError(f"Invalid Flash Descriptor signature: 0x{sig:08X}")
    
    # Parse FLMAP0 (Region Base Addresses)
    flmap0 = struct.unpack('<I', firmware_data[0x14:0x18])[0]
    
    # Parse FLMAP1 (Component Section)
    flmap1 = struct.unpack('<I', firmware_data[0x18:0x1C])[0]
    
    # Region offsets
    frba = ((flmap0 >> 16) & 0xFF) << 4
    
    # Read ME region bounds from FREG2
    freg2_offset = frba + 0x08  # FREG2 = ME region
    freg2 = struct.unpack('<I', firmware_data[freg2_offset:freg2_offset+4])[0]
    
    me_base = (freg2 & 0x7FFF) << 12
    me_limit = ((freg2 >> 16) & 0x7FFF) << 12
    
    return {
        'me_base': me_base,
        'me_limit': me_limit,
        'me_size': me_limit - me_base + 0x1000
    }

def extract_me_region(firmware_path, output_path):
    """Extract ME region from firmware"""
    
    print(f"[*] Reading firmware: {firmware_path}")
    firmware_data = Path(firmware_path).read_bytes()
    
    print(f"[*] Firmware size: {len(firmware_data):,} bytes")
    
    descriptor = parse_flash_descriptor(firmware_data)
    
    print(f"[*] ME Region found:")
    print(f"    Base:   0x{descriptor['me_base']:08X}")
    print(f"    Limit:  0x{descriptor['me_limit']:08X}")
    print(f"    Size:   {descriptor['me_size']:,} bytes ({descriptor['me_size']//1024//1024} MB)")
    
    # Extract
    me_data = firmware_data[descriptor['me_base']:descriptor['me_limit']+1]
    
    Path(output_path).write_bytes(me_data)
    
    print(f"[✓] ME region extracted to: {output_path}")
    
    # Check for EverCrypt signature
    if b'EVERCRYPT-ME-2025' in me_data:
        print("[!] EverCrypt signature detected in ME region!")
    else:
        print("[✓] Clean ME region (no EverCrypt)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: extract_me.py <firmware.bin> <output_me.bin>")
        sys.exit(1)
    
    extract_me_region(sys.argv[1], sys.argv[2])