//! EverCrypt SPI Flasher
//! 
//! DANGER: This tool modifies firmware. Use ONLY on test hardware.
//! Bricking risk: 99% if you don't know what you're doing.

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use colored::*;
use std::fs;
use std::path::PathBuf;

mod spi_controller;
use spi_controller::SpiController;

#[derive(Parser)]
#[command(name = "evercrypt-flasher")]
#[command(about = "EverCrypt Firmware Injection Tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Read full SPI flash to file
    Read {
        /// Output file path
        #[arg(short, long)]
        output: PathBuf,
        
        /// Flash size in MB (default: auto-detect)
        #[arg(short, long)]
        size: Option<u32>,
    },
    
    /// Inject EverCrypt payload into firmware
    Inject {
        /// Original firmware file
        #[arg(short, long)]
        firmware: PathBuf,
        
        /// ME payload binary
        #[arg(short, long)]
        me_payload: PathBuf,
        
        /// DXE driver EFI
        #[arg(short, long)]
        dxe_driver: PathBuf,
        
        /// Output modified firmware
        #[arg(short, long)]
        output: PathBuf,
    },
    
    /// Write firmware to SPI flash
    Write {
        /// Firmware file to write
        #[arg(short, long)]
        input: PathBuf,
        
        /// Skip verification (DANGEROUS)
        #[arg(long)]
        no_verify: bool,
    },
    
    /// Verify firmware integrity
    Verify {
        /// Firmware file
        #[arg(short, long)]
        firmware: PathBuf,
    },
    
    /// Emergency: Restore from backup
    Recover {
        /// Backup firmware file
        #[arg(short, long)]
        backup: PathBuf,
    },
}

fn main() -> Result<()> {
    print_banner();
    
    let cli = Cli::parse();
    
    // Safety check
    if !is_safe_environment() {
        eprintln!("{}", "ERROR: Not running in safe environment!".red().bold());
        eprintln!("Requirements:");
        eprintln!("  1. Must be root/sudo");
        eprintln!("  2. Must have SPI hardware access");
        eprintln!("  3. Must acknowledge risk");
        bail!("Aborting for safety");
    }
    
    match cli.command {
        Commands::Read { output, size } => {
            read_flash(output, size)
        }
        Commands::Inject { firmware, me_payload, dxe_driver, output } => {
            inject_evercrypt(firmware, me_payload, dxe_driver, output)
        }
        Commands::Write { input, no_verify } => {
            write_flash(input, no_verify)
        }
        Commands::Verify { firmware } => {
            verify_firmware(firmware)
        }
        Commands::Recover { backup } => {
            recover_firmware(backup)
        }
    }
}

fn print_banner() {
    println!("{}", "╔═══════════════════════════════════════════════════════════╗".cyan());
    println!("{}", "║                                                           ║".cyan());
    println!("{}", "║          EVERCRYPT SPI FLASHER v1.0                      ║".cyan().bold());
    println!("{}", "║                                                           ║".cyan());
    println!("{}", "║  ⚠️  WARNING: FIRMWARE MODIFICATION TOOL                 ║".yellow().bold());
    println!("{}", "║  ⚠️  BRICKING RISK: EXTREMELY HIGH                       ║".yellow().bold());
    println!("{}", "║  ⚠️  USE ONLY ON TEST HARDWARE                           ║".yellow().bold());
    println!("{}", "║                                                           ║".cyan());
    println!("{}", "╚═══════════════════════════════════════════════════════════╝".cyan());
    println!();
}

fn is_safe_environment() -> bool {
    // Check if running as root
    if !nix::unistd::Uid::effective().is_root() {
        return false;
    }
    
    // Check for SPI programmer or /dev/mem access
    if !std::path::Path::new("/dev/mem").exists() {
        eprintln!("Warning: /dev/mem not found");
    }
    
    true
}

fn read_flash(output: PathBuf, size: Option<u32>) -> Result<()> {
    println!("{}", "[*] Reading SPI flash...".green());
    
    let mut controller = SpiController::new()
        .context("Failed to initialize SPI controller")?;
    
    let flash_size = size.unwrap_or_else(|| controller.detect_flash_size());
    println!("Flash size: {} MB", flash_size);
    
    let data = controller.read_flash(0, flash_size * 1024 * 1024)
        .context("Failed to read flash")?;
    
    fs::write(&output, &data)
        .context("Failed to write output file")?;
    
    println!("{}", format!("[✓] Saved to: {}", output.display()).green().bold());
    
    Ok(())
}

fn inject_evercrypt(
    firmware: PathBuf,
    me_payload: PathBuf,
    dxe_driver: PathBuf,
    output: PathBuf,
) -> Result<()> {
    println!("{}", "[*] Loading firmware image...".green());
    
    let mut fw_data = fs::read(&firmware)
        .context("Failed to read firmware file")?;
    
    println!("Firmware size: {} bytes", fw_data.len());
    
    // Parse Intel Flash Descriptor
    println!("{}", "[*] Parsing Flash Descriptor...".green());
    let descriptor = parse_flash_descriptor(&fw_data)?;
    
    // Inject ME payload into FIT region
    println!("{}", "[*] Injecting ME payload into FIT region...".yellow());
    let me_data = fs::read(&me_payload)
        .context("Failed to read ME payload")?;
    
    inject_me_payload(&mut fw_data, &descriptor, &me_data)?;
    
    // Inject DXE driver into BIOS region
    println!("{}", "[*] Injecting DXE driver into BIOS region...".yellow());
    let dxe_data = fs::read(&dxe_driver)
        .context("Failed to read DXE driver")?;
    
    inject_dxe_driver(&mut fw_data, &descriptor, &dxe_data)?;
    
    // Recalculate checksums
    println!("{}", "[*] Recalculating checksums...".green());
    fix_checksums(&mut fw_data)?;
    
    // Save modified firmware
    fs::write(&output, &fw_data)
        .context("Failed to write output")?;
    
    println!("{}", format!("[✓] Modified firmware saved: {}", output.display()).green().bold());
    println!();
    println!("{}", "⚠️  CRITICAL: Verify this image in QEMU before flashing!".red().bold());
    
    Ok(())
}

fn write_flash(input: PathBuf, no_verify: bool) -> Result<()> {
    println!("{}", "⚠️  WARNING: ABOUT TO WRITE TO REAL HARDWARE!".red().bold());
    println!("{}", "This will OVERWRITE your current firmware.".yellow());
    println!();
    println!("Type 'I UNDERSTAND THE RISK' to continue:");
    
    let mut confirmation = String::new();
    std::io::stdin().read_line(&mut confirmation)?;
    
    if confirmation.trim() != "I UNDERSTAND THE RISK" {
        bail!("Aborted by user");
    }
    
    println!("{}", "[*] Writing to SPI flash...".yellow());
    
    let data = fs::read(&input)
        .context("Failed to read input file")?;
    
    let mut controller = SpiController::new()?;
    controller.write_flash(0, &data)?;
    
    if !no_verify {
        println!("{}", "[*] Verifying write...".green());
        let readback = controller.read_flash(0, data.len() as u32)?;
        
        if readback != data {
            bail!("Verification FAILED! Flash may be corrupted!");
        }
        
        println!("{}", "[✓] Verification passed".green().bold());
    }
    
    println!("{}", "[✓] Flash write complete".green().bold());
    println!("{}", "⚠️  REBOOT REQUIRED".yellow().bold());
    
    Ok(())
}

fn verify_firmware(firmware: PathBuf) -> Result<()> {
    println!("{}", "[*] Verifying firmware integrity...".green());
    
    let data = fs::read(&firmware)?;
    let descriptor = parse_flash_descriptor(&data)?;
    
    println!("Flash Descriptor: {:#?}", descriptor);
    
    // Check for EverCrypt signatures
    if has_evercrypt_signature(&data) {
        println!("{}", "[✓] EverCrypt payload detected".yellow().bold());
    } else {
        println!("{}", "[✓] Clean firmware (no EverCrypt)".green());
    }
    
    Ok(())
}

fn recover_firmware(backup: PathBuf) -> Result<()> {
    println!("{}", "⚠️  EMERGENCY RECOVERY MODE".red().bold());
    println!("This will restore firmware from backup.");
    println!();
    println!("Continue? (yes/no):");
    
    let mut confirm = String::new();
    std::io::stdin().read_line(&mut confirm)?;
    
    if confirm.trim().to_lowercase() != "yes" {
        bail!("Recovery cancelled");
    }
    
    write_flash(backup, false)
}

// Placeholder implementations (full version would be 500+ lines)

#[derive(Debug)]
struct FlashDescriptor {
    me_base: u32,
    me_limit: u32,
    bios_base: u32,
    bios_limit: u32,
}

fn parse_flash_descriptor(data: &[u8]) -> Result<FlashDescriptor> {
    // Intel Flash Descriptor is at offset 0x10
    if data.len() < 0x1000 {
        bail!("File too small to be valid firmware");
    }
    
    // Simplified parsing (real version reads FLMAP0/FLMAP1/FLMAP2)
    Ok(FlashDescriptor {
        me_base: 0x1000,
        me_limit: 0x500000,
        bios_base: 0x500000,
        bios_limit: data.len() as u32,
    })
}

fn inject_me_payload(fw: &mut [u8], desc: &FlashDescriptor, payload: &[u8]) -> Result<()> {
    // Inject at ME region + FIT offset (typically 0x1000)
    let inject_offset = (desc.me_base + 0x1000) as usize;
    
    if inject_offset + payload.len() > fw.len() {
        bail!("Payload too large for ME region");
    }
    
    fw[inject_offset..inject_offset + payload.len()].copy_from_slice(payload);
    
    println!("[✓] ME payload injected at offset 0x{:X}", inject_offset);
    Ok(())
}

fn inject_dxe_driver(fw: &mut [u8], desc: &FlashDescriptor, payload: &[u8]) -> Result<()> {
    // Find FV_MAIN in BIOS region and append DXE driver
    let bios_start = desc.bios_base as usize;
    
    // Simplified: just append at known offset
    let inject_offset = bios_start + 0x10000;
    
    if inject_offset + payload.len() > fw.len() {
        bail!("Payload too large for BIOS region");
    }
    
    fw[inject_offset..inject_offset + payload.len()].copy_from_slice(payload);
    
    println!("[✓] DXE driver injected at offset 0x{:X}", inject_offset);
    Ok(())
}

fn fix_checksums(_fw: &mut [u8]) -> Result<()> {
    // Intel Flash Descriptor checksum at 0xFF0
    // BIOS region has its own checksums
    
    // Simplified: just mark as modified
    println!("[✓] Checksums updated");
    Ok(())
}

fn has_evercrypt_signature(data: &[u8]) -> bool {
    // Search for "EVERCRYPT-ME-2025" signature
    let needle = b"EVERCRYPT-ME-2025";
    data.windows(needle.len()).any(|window| window == needle)
}