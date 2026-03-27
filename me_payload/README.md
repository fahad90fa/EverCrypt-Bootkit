# EverCrypt ME Payload - Ring -3 Eternal Persistence

## Overview
This directory contains the Intel Management Engine (ME) 8051 payload that provides **eternal persistence** by residing in the ME firmware region and surviving:
- Full BIOS/UEFI SPI reflash
- OS reinstallation (Windows, Linux, macOS)
- Hard drive replacement
- ME firmware updates (via HAP bit bypass)
- Physical SPI programmer attacks (via FIT table protection)

## Intel ME Architecture (2024-2025)

### Target Platforms
- **Intel Core Ultra (Meteor Lake)**: ME 17.x
- **Intel 13th/14th Gen (Raptor Lake)**: ME 16.x  
- **Intel 12th Gen (Alder Lake)**: ME 15.x

### Memory Map