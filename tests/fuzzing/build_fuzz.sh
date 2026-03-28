#!/bin/bash
echo "[*] Building fuzzing harness..."

# Standalone test first
gcc -O2 -DSTANDALONE_TEST fuzz_smm_comm.c -o fuzz_standalone
echo "[✓] Standalone test binary built"

echo "[*] Running self-test..."
./fuzz_standalone

# AFL++ build (if available)
if command -v afl-clang-fast &> /dev/null; then
    afl-clang-fast -O2 -DAFL_HARNESS fuzz_smm_comm.c -o fuzz_smm
    mkdir -p corpus
    echo -ne '\x01\x00\x00\x00\x04\x00\x00\x00\xAA\xBB\xCC\xDD' > corpus/seed1.bin
    echo -ne '\x03\x00\x00\x00\x00\x00\x00\x00' > corpus/seed2.bin
    echo "[✓] AFL++ harness built"
    echo "Run: afl-fuzz -i corpus/ -o findings/ -- ./fuzz_smm"
else
    echo "[!] AFL++ not found. Install: sudo pacman -S afl++"
    echo "[✓] Standalone test passed - fuzzing skipped"
fi
