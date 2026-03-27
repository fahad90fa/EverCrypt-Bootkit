//! SPI Controller Interface
//! Supports: /dev/mem, Dediprog, CH341A

use anyhow::{Result, bail};

pub struct SpiController {
    backend: SpiBackend,
}

enum SpiBackend {
    DevMem,
    Dediprog,
    CH341A,
}

impl SpiController {
    pub fn new() -> Result<Self> {
        // Try /dev/mem first (Intel hardware SPI)
        if std::path::Path::new("/dev/mem").exists() {
            println!("[*] Using /dev/mem backend");
            return Ok(Self {
                backend: SpiBackend::DevMem,
            });
        }
        
        // Try external programmers
        if Self::detect_dediprog() {
            println!("[*] Using Dediprog");
            return Ok(Self {
                backend: SpiBackend::Dediprog,
            });
        }
        
        if Self::detect_ch341a() {
            println!("[*] Using CH341A");
            return Ok(Self {
                backend: SpiBackend::CH341A,
            });
        }
        
        bail!("No SPI controller found. Supported: /dev/mem, Dediprog, CH341A");
    }
    
    pub fn detect_flash_size(&self) -> u32 {
        // Read JEDEC ID and decode size
        // Simplified: return 16 MB (common for modern systems)
        16
    }
    
    pub fn read_flash(&mut self, offset: u32, size: u32) -> Result<Vec<u8>> {
        match self.backend {
            SpiBackend::DevMem => self.read_via_devmem(offset, size),
            SpiBackend::Dediprog => self.read_via_dediprog(offset, size),
            SpiBackend::CH341A => self.read_via_ch341a(offset, size),
        }
    }
    
    pub fn write_flash(&mut self, offset: u32, data: &[u8]) -> Result<()> {
        match self.backend {
            SpiBackend::DevMem => self.write_via_devmem(offset, data),
            SpiBackend::Dediprog => self.write_via_dediprog(offset, data),
            SpiBackend::CH341A => self.write_via_ch341a(offset, data),
        }
    }
    
    fn detect_dediprog() -> bool {
        // Check for Dediprog via lsusb
        std::process::Command::new("lsusb")
            .output()
            .ok()
            .and_then(|out| String::from_utf8(out.stdout).ok())
            .map(|s| s.contains("0483:dada"))
            .unwrap_or(false)
    }
    
    fn detect_ch341a() -> bool {
        std::process::Command::new("lsusb")
            .output()
            .ok()
            .and_then(|out| String::from_utf8(out.stdout).ok())
            .map(|s| s.contains("1a86:5512"))
            .unwrap_or(false)
    }
    
    fn read_via_devmem(&mut self, offset: u32, size: u32) -> Result<Vec<u8>> {
        // Placeholder: Real version uses mmap() on /dev/mem
        println!("[STUB] Reading {} bytes from offset 0x{:X}", size, offset);
        Ok(vec![0xFF; size as usize])
    }
    
    fn write_via_devmem(&mut self, offset: u32, data: &[u8]) -> Result<()> {
        println!("[STUB] Writing {} bytes to offset 0x{:X}", data.len(), offset);
        Ok(())
    }
    
    fn read_via_dediprog(&mut self, _offset: u32, _size: u32) -> Result<Vec<u8>> {
        // Uses dpcmd command-line tool
        bail!("Dediprog support not yet implemented");
    }
    
    fn write_via_dediprog(&mut self, _offset: u32, _data: &[u8]) -> Result<()> {
        bail!("Dediprog write not yet implemented");
    }
    
    fn read_via_ch341a(&mut self, _offset: u32, _size: u32) -> Result<Vec<u8>> {
        bail!("CH341A support not yet implemented");
    }
    
    fn write_via_ch341a(&mut self, _offset: u32, _data: &[u8]) -> Result<()> {
        bail!("CH341A write not yet implemented");
    }
}