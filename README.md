# Raspberry Pi Boot Disk with Recovery System

This project creates a Raspberry Pi boot disk with an integrated recovery system that allows you to easily restore your system to its original state.

## Features

- **Automated Ubuntu Server Download**: Downloads official Ubuntu Server images from Canonical
- **Dual-Partition System**: Creates separate main and recovery partitions
- **One-Click Recovery**: Simple command to enable recovery mode
- **Automatic Backup**: Creates system backups for easy restoration
- **Boot Menu Integration**: Seamless switching between normal and recovery modes
- **Cross-Platform Support**: Works on Linux, macOS, and Windows (WSL)

## Quick Start

### 1. Download Ubuntu Server Image

```bash
# Download latest Ubuntu 22.04 LTS for Raspberry Pi 4
./scripts/download-image.sh

# Or specify version and Pi model
./scripts/download-image.sh -r 24.04 -t pi5
```

### 2. Create Boot Disk

```bash
# Create boot disk (replace /dev/sdX with your actual device)
sudo ./scripts/create-boot-disk.sh /dev/sdX

# With custom options
sudo ./scripts/create-boot-disk.sh -s 8 -n "my-pi" /dev/sdX
```

### 3. Use Recovery System

Once your Pi is running:

```bash
# Enable recovery mode and reboot
sudo recovery-mode enable
sudo reboot

# Check recovery status
sudo recovery-mode status

# Disable recovery mode
sudo recovery-mode disable
```

## System Architecture

### Partition Layout

| Partition | Size | Purpose | Label |
|-----------|------|---------|-------|
| 1 | 256MB | EFI System | EFI |
| 2 | Remaining | Main Ubuntu System | {name}-main |
| 3 | 4GB (configurable) | Recovery System | {name}-recovery |

### Boot Process

1. **Normal Boot**: Raspberry Pi boots from main partition (partition 2)
2. **Recovery Trigger**: User runs `recovery-mode enable` 
3. **Recovery Boot**: Next boot automatically switches to recovery partition (partition 3)
4. **System Restore**: Recovery system can restore main partition from backup

## Installation Requirements

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install wget xz-utils parted dosfstools e2fsprogs rsync tar coreutils
```

### macOS
```bash
brew install wget xz parted
```

### Windows (WSL)
```bash
sudo apt update
sudo apt install wget xz-utils parted dosfstools e2fsprogs rsync tar coreutils
```

## Usage Guide

### Downloading Images

The download script automatically fetches official Ubuntu Server images:

```bash
# List available releases
./scripts/download-image.sh -l

# Download specific version
./scripts/download-image.sh -r 22.04 -t pi4

# Force re-download
./scripts/download-image.sh -f
```

**Supported Options:**
- `-r, --release`: Ubuntu version (20.04, 22.04, 24.04)
- `-t, --type`: Pi model (pi4, pi5)
- `-a, --arch`: Architecture (arm64)
- `-f, --force`: Force re-download
- `-l, --list`: List available releases

### Creating Boot Disks

The boot disk creation script sets up the complete recovery system:

```bash
# Basic usage
sudo ./scripts/create-boot-disk.sh /dev/sdX

# Advanced options
sudo ./scripts/create-boot-disk.sh \
  -i custom-image.img \
  -s 8 \
  -n "production-pi" \
  /dev/sdX
```

**Options:**
- `-i, --image`: Custom Ubuntu image file
- `-s, --size`: Recovery partition size in GB (default: 4)
- `-n, --name`: System name for identification
- `-y, --yes`: Skip confirmation prompts
- `-v, --verbose`: Verbose output

**⚠️ WARNING**: This will completely erase the target device!

### Recovery Operations

#### Entering Recovery Mode

From the main system:
```bash
# Enable recovery for next boot
sudo recovery-mode enable

# Reboot into recovery
sudo reboot
```

#### Recovery System Tools

Once in recovery mode:

```bash
# Show system status
recovery-tool status

# Create backup of main system
recovery-tool backup
recovery-tool backup -n "before-update" -f

# Restore main system from backup
recovery-tool restore
recovery-tool restore -b specific_backup.tar.gz

# List available backups
recovery-tool list

# Clean old backups
recovery-tool clean

# View logs
recovery-tool logs
```

#### Manual Recovery Scripts

For advanced users:

```bash
# Create backup manually
/mnt/recovery/scripts/backup.sh -n "manual-backup" -c 9

# Restore from specific backup  
/mnt/recovery/scripts/restore.sh -b backup_file.tar.gz -f
```

## Configuration Files

### Boot Configuration (`configs/config.txt`)
- Raspberry Pi boot settings
- Recovery mode detection
- Hardware-specific configurations

### Boot Selection (`configs/boot_selection.sh`)
- Determines boot target (main vs recovery)
- Handles recovery mode triggers
- Manages boot parameters

## Directory Structure

```
build-pi-boot-disk/
├── scripts/
│   ├── download-image.sh      # Download Ubuntu images
│   └── create-boot-disk.sh    # Create recovery boot disk
├── recovery/
│   ├── backup.sh              # Create system backups
│   ├── restore.sh             # Restore from backups
│   ├── recovery-mode          # Recovery mode control
│   └── recovery-tool.sh       # Main recovery interface
├── configs/
│   ├── config.txt             # Pi boot configuration
│   └── boot_selection.sh      # Boot selection logic
├── images/                    # Downloaded Ubuntu images
└── README.md                  # This file
```

## Troubleshooting

### Common Issues

1. **Script Permission Denied**
   ```bash
   chmod +x scripts/*.sh recovery/*.sh configs/*.sh
   ```

2. **Device Not Found**
   ```bash
   # List available devices
   lsblk
   
   # Check if device is mounted
   mount | grep /dev/sdX
   
   # Unmount if necessary
   sudo umount /dev/sdX*
   ```

3. **Insufficient Space**
   - Use smaller recovery partition: `-s 2`
   - Use higher compression: `recovery-tool backup -c 9`
   - Clean old backups: `recovery-tool clean`

4. **Recovery Mode Not Working**
   ```bash
   # Check trigger file
   ls -la /boot/recovery_mode
   
   # Manually create trigger
   sudo touch /boot/recovery_mode
   sudo reboot
   ```

### Boot Issues

1. **Pi Won't Boot**
   - Check SD card connections
   - Verify config.txt syntax
   - Use HDMI to see boot messages

2. **Wrong Partition Boot**
   - Check boot logs: `cat /boot/boot.log`
   - Verify partition labels: `lsblk -f`
   - Manually edit cmdline.txt

### Recovery Issues

1. **Recovery Partition Not Accessible**
   ```bash
   # Mount manually
   sudo mkdir -p /mnt/recovery
   sudo mount /dev/sdX3 /mnt/recovery
   ```

2. **Backup/Restore Fails**
   - Check available space: `df -h`
   - Verify file permissions
   - Check logs in `/mnt/recovery/logs/`

## Advanced Usage

### Custom Images

Use your own pre-configured Ubuntu images:

```bash
sudo ./scripts/create-boot-disk.sh -i /path/to/custom.img /dev/sdX
```

### Automated Backups

Set up automatic backups with cron:

```bash
# Add to crontab (run daily at 2 AM)
0 2 * * * /usr/local/bin/recovery-tool backup -n "daily-$(date +\%Y\%m\%d)"
```

### Network Recovery

Access recovery system over SSH:

1. Enable SSH in recovery mode
2. Configure static IP
3. Access remotely for system management

### Custom Recovery Scripts

Add your own recovery scripts to `/mnt/recovery/scripts/`:

```bash
# Custom maintenance script
#!/bin/bash
echo "Running custom maintenance..."
# Your code here
```

## Security Considerations

- **Encryption**: Consider encrypting sensitive partitions
- **Access Control**: Limit recovery mode access
- **Network Security**: Secure SSH access if enabled
- **Backup Security**: Encrypt backup files if they contain sensitive data

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Support

- **Issues**: Report bugs and feature requests on GitHub
- **Documentation**: Check this README and inline comments
- **Community**: Join discussions in GitHub Discussions

## Changelog

### v1.0.0
- Initial release
- Ubuntu Server image download
- Dual-partition boot disk creation
- Recovery system with backup/restore
- Boot mode selection
- Comprehensive documentation
