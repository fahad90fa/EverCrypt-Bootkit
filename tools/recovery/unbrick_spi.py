#!/usr/bin/env python3
"""
EverCrypt Emergency Recovery Tool
Restores clean firmware via SPI programmer
"""

import sys
import subprocess
from pathlib import Path

def detect_programmer():
    """Detect connected SPI programmer"""
    
    # Check for Dediprog
    result = subprocess.run(['lsusb'], capture_output=True, text=True)
    if '0483:dada' in result.stdout:
        return 'dediprog'
    if '1a86:5512' in result.stdout:
        return 'ch341a'
    
    return None

def unbrick_firmware(backup_path):
    """Emergency firmware restoration"""
    
    print("╔═══════════════════════════════════════════════╗")
    print("║   EVERCRYPT EMERGENCY RECOVERY TOOL           ║")
    print("╚═══════════════════════════════════════════════╝")
    print()
    
    if not Path(backup_path).exists():
        print("[!] Backup file not found!")
        sys.exit(1)
    
    programmer = detect_programmer()
    
    if not programmer:
        print("[!] No SPI programmer detected!")
        print("    Supported: Dediprog, CH341A")
        sys.exit(1)
    
    print(f"[*] Detected: {programmer}")
    print(f"[*] Backup: {backup_path}")
    print()
    print("⚠️  This will ERASE and REWRITE your entire SPI flash!")
    print()
    print("Type 'UNBRICK NOW' to continue:")
    
    confirm = input()
    if confirm != 'UNBRICK NOW':
        print("Aborted.")
        sys.exit(0)
    
    print()
    print("[*] Flashing...")
    
    if programmer == 'dediprog':
        cmd = ['dpcmd', '-u', backup_path]
    else:  # ch341a
        cmd = ['flashrom', '-p', 'ch341a_spi', '-w', backup_path]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("[✓] Flash complete!")
        print("[✓] Your system should be recovered.")
        print()
        print("Remove SPI programmer and reboot now.")
    else:
        print("[!] Flash FAILED!")
        print(result.stderr)
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: unbrick_spi.py <clean_backup.bin>")
        sys.exit(1)
    
    unbrick_firmware(sys.argv[1])