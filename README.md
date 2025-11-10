# Pi Boot Disk Builder

A complete system for creating customized Raspberry Pi boot disks using official Ubuntu Server images with your personal configurations preserved.

## Quick Start

### Prerequisites
- Linux system (tested on Ubuntu)
- Root/sudo access
- Internet connection for image downloads
- Target disk/SD card for Pi boot disk creation

### One-Command Setup
```bash
cd utility
sudo ./complete_pi_workflow.sh /dev/sdX 24.04
```
Replace `/dev/sdX` with your target device (e.g., `/dev/sdb`, `/dev/sdc`) and `24.04` with desired Ubuntu version.

## What This System Does

### 🎯 **Core Features**
- **Official Ubuntu Images**: Downloads verified Ubuntu Server images directly from Canonical
- **Customization Preservation**: Captures your user accounts, SSH keys, network settings, and installed packages
- **Dual-Partition Design**: Creates active and backup partitions for factory reset capability
- **Complete Automation**: Single command from download to ready-to-use Pi disk

### 🛡️ **Built-in Safety**
- Image verification with checksums
- Backup partition for system recovery
- Factory reset functionality (`sudo pi-reset.sh`)
- External reset capability for maximum safety

## Usage Guide

### Method 1: Complete Workflow (Recommended)
```bash
# Create a complete Pi disk with your customizations
sudo ./complete_pi_workflow.sh /dev/sdX 24.04
```

This will:
1. Download Ubuntu 24.04 LTS Server image
2. Extract your current system customizations
3. Create a dual-partition Pi disk
4. Apply your customizations to both partitions
5. Install reset scripts for factory reset capability

### Method 2: Step-by-Step Process
```bash
# Step 1: Download Ubuntu image
./download_ubuntu_image.sh 24.04

# Step 2: Extract your customizations  
./extract_customizations.sh

# Step 3: Create the Pi disk
sudo ./create_pi_disk.sh /path/to/ubuntu/image.img /dev/sdX
```

### Method 3: Using Existing Images
```bash
# If you already have a Ubuntu image
sudo ./create_pi_disk.sh /path/to/your/image.img /dev/sdX
```

## Ubuntu Image Downloader

The `download_ubuntu_image.sh` script provides official Ubuntu Server image downloads with Raspberry Pi Imager integration.

### 🎯 **Key Features**
- **Official Pi Imager Integration**: Uses Raspberry Pi Foundation's official image validation
- **Automatic Installation**: Installs Pi Imager if not present
- **Version-Specific Downloads**: Downloads exact Ubuntu versions you specify
- **Architecture Support**: Both ARM64 (64-bit) and ARMHF (32-bit) architectures
- **Smart Caching**: Reuses existing images when version/architecture matches

### 📥 **Usage Examples**
```bash
# Download latest recommended version (24.04 LTS)
sudo ./download_ubuntu_image.sh

# Download specific version
sudo ./download_ubuntu_image.sh 25.10

# Specify version and architecture
sudo ./download_ubuntu_image.sh 24.04 arm64

# Custom download directory
sudo ./download_ubuntu_image.sh 24.04 arm64 /tmp/ubuntu-images
```

### 🔍 **Help and Options**
```bash
# Show all available options and examples
./download_ubuntu_image.sh --help
```

### 💾 **Download Locations**
- **Default**: `~/ubuntu-images/`
- **Naming**: `ubuntu-VERSION-preinstalled-server-ARCH+raspi.img`
- **Formats**: Downloads `.img.xz` (compressed), extracts to `.img`

## Supported Ubuntu Versions

| Version | Status | Image Size | Notes |
|---------|--------|------------|-------|
| 22.04 LTS | ✅ Supported | ~2.2GB | Long-term support (older) |
| 24.04 LTS | ✅ **Recommended** | ~2.3GB | Long-term support |
| 24.10 | ✅ Supported | ~2.3GB | Latest interim release |
| 25.10 | ✅ **Tested** | ~2.4GB | Latest development version |

**Architecture Support:**
- **ARM64** (64-bit): Raspberry Pi 3B+, 4, 5, Zero 2W
- **ARMHF** (32-bit): Older Raspberry Pi models (Pi 1, 2, early Pi 3)

## Customizations Preserved

### 👤 **User Accounts**
- User accounts with correct UIDs/GIDs
- Home directories and personal files
- User group memberships
- Shell preferences

### 🔐 **Security Settings**
- SSH public/private keys
- SSH server configuration
- Authorized keys for remote access
- User passwords (hashed)

### 🌐 **Network Configuration**
- WiFi credentials and settings
- Netplan configuration
- Static IP assignments
- Network interface settings

### 📦 **Software & Packages**
- Complete list of installed packages
- Snap packages
- Custom software configurations
- Cron jobs and scheduled tasks

## Disk Layout

The created Pi disks use a three-partition layout optimized for reliability and expansion:

| Partition | Label | Size | Purpose | Filesystem |
|-----------|-------|------|---------|------------|
| 1 | `system-boot` | 512MB | Boot partition | FAT32 |
| 2 | `writable_backup` | 3.5GB | Backup root | ext4 |
| 3 | `writable` | 3.5GB+ | Active root | ext4 |

**Benefits:**
- ✅ **Boot Partition**: Standard Pi boot requirements
- ✅ **Active Partition**: Your customized system
- ✅ **Backup Partition**: Factory reset capability
- ✅ **Expandable**: Last partition can grow to fill larger disks

## Factory Reset System

### Internal Reset (from the Pi)
```bash
sudo pi-reset.sh
```
**Use when:** Pi is running and you want to reset to factory state

### External Reset (safer method)
```bash
# From another Linux system with Pi disk connected
sudo ./external_pi_reset.sh /dev/sdX
```
**Use when:** Pi disk is connected to another system (recommended)

## File Structure

```
build-pi-boot-disk/
├── README.md                    # This guide
├── utility/
│   ├── complete_pi_workflow.sh  # Main automation script
│   ├── download_ubuntu_image.sh # Official Ubuntu image downloader (Pi Imager)
│   ├── extract_customizations.sh # System customization extractor
│   ├── create_pi_disk.sh        # Pi disk creator
│   ├── external_pi_reset.sh     # External reset tool
│   └── backup_pi_image.sh       # Legacy backup script
├── PARTITION_LAYOUT_UPDATE.md   # Technical partition details
└── PI_RESET_SAFETY.md          # Reset safety guidelines
```

## Common Use Cases

### 🏠 **Home Lab Setup**
```bash
# Create multiple Pi disks with your standard configuration
sudo ./complete_pi_workflow.sh /dev/sdb 24.04  # Pi #1
sudo ./complete_pi_workflow.sh /dev/sdc 24.04  # Pi #2
```

### 🏢 **Production Deployment**
```bash
# Extract customizations from configured system
./extract_customizations.sh

# Create production disks with same configuration
sudo ./create_pi_disk.sh /path/to/ubuntu.img /dev/sdb
sudo ./create_pi_disk.sh /path/to/ubuntu.img /dev/sdc
```

### 🔧 **Development & Testing**
```bash
# Create test disk with reset capability
sudo ./complete_pi_workflow.sh /dev/sdb 24.04

# Later: reset to clean state for testing
sudo pi-reset.sh  # (from Pi) or sudo ./external_pi_reset.sh /dev/sdb
```

## Troubleshooting

### Image Download Issues
- **Problem**: Download fails or is corrupted
- **Solution**: Delete partial downloads and retry
```bash
rm -rf ~/ubuntu-images/
sudo ./download_ubuntu_image.sh 24.04
```

- **Problem**: Permission denied when downloading
- **Solution**: Use sudo (directory may be root-owned)
```bash
sudo ./download_ubuntu_image.sh 24.04
```

- **Problem**: Pi Imager not found
- **Solution**: Script will auto-install, or install manually
```bash
# Auto-installation (happens automatically)
sudo ./download_ubuntu_image.sh 24.04

# Manual installation
sudo apt update && sudo apt install rpi-imager
```

### Disk Creation Errors
- **Problem**: "Device busy" or mount errors
- **Solution**: Unmount all partitions first
```bash
sudo umount /dev/sdX*
sudo ./create_pi_disk.sh image.img /dev/sdX
```

### Reset Script Issues
- **Problem**: Reset fails or system becomes unstable
- **Solution**: Use external reset method
```bash
# Power off Pi, connect disk to another system
sudo ./external_pi_reset.sh /dev/sdX
```

### Customization Problems
- **Problem**: Settings not applied correctly
- **Solution**: Check extraction log and retry
```bash
./extract_customizations.sh
cat /home/pi/system-customizations/EXTRACTION_SUMMARY.txt
```

## Advanced Usage

### Custom Image Sources
```bash
# Use your own Ubuntu image
sudo ./create_pi_disk.sh /path/to/custom/ubuntu.img /dev/sdX
```

### Selective Customizations
```bash
# Extract to custom directory
./extract_customizations.sh /custom/output/path

# Edit restore_customizations.sh to modify what gets applied
nano /custom/output/path/restore_customizations.sh
```

### Disk Expansion
```bash
# Expand last partition to fill larger disk
sudo parted /dev/sdX resizepart 3 100%
sudo resize2fs /dev/sdX3
```

## Security Considerations

- 🔒 **SSH Keys**: Private keys are preserved - ensure physical security of disks
- 🔐 **Passwords**: User passwords are preserved via shadow file
- 🌐 **WiFi**: Network credentials are stored in plain text in Netplan configs
- 📦 **Packages**: Only official Ubuntu repositories are used by default
- 🛡️ **Image Sources**: Downloads from official Ubuntu and Pi Foundation repositories
- 🔐 **Pi Imager**: Uses official Raspberry Pi Imager for image validation and sourcing

## Support & Documentation

- **Partition Layout**: See `PARTITION_LAYOUT_UPDATE.md`
- **Reset Safety**: See `PI_RESET_SAFETY.md`
- **Ubuntu Images**: [Official Ubuntu Pi Images](https://ubuntu.com/download/raspberry-pi)
- **Pi Documentation**: [Raspberry Pi Foundation](https://www.raspberrypi.org/documentation/)

## License

This project is designed for personal and educational use. Ubuntu images remain under their respective licenses from Canonical.

---

**Quick Reference:**
```bash
# Complete setup in one command
sudo ./complete_pi_workflow.sh /dev/sdX 24.04

# Download Ubuntu image with Pi Imager
sudo ./download_ubuntu_image.sh 25.10 arm64

# Factory reset (safe external method)
sudo ./external_pi_reset.sh /dev/sdX

# Factory reset (from Pi itself)
sudo pi-reset.sh
```

*Happy Pi building! 🥧*