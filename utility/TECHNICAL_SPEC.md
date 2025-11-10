# Pi Disk Creation Script - Technical Specification

## Document Information
- **Document**: Technical Specification
- **Script**: create_pi_disk.sh
- **Version**: 1.0
- **Date**: November 8, 2025
- **Purpose**: Detailed technical documentation for developers and system administrators

## Architecture Overview

### System Flow
```
[Backup Image] → [Validation] → [Partition Creation] → [File System Setup] → [Data Copy] → [Reset Script Install] → [Bootable Pi Disk]
```

### Component Interaction
```
create_pi_disk.sh
├── Input Validation Module
├── Partition Management Module  
├── File System Module
├── Data Synchronization Module
├── Reset Script Generator
└── Verification Module
```

## Technical Specifications

### Partition Layout Specification

| Partition | Start Sector | Size | Type | File System | Label | Flags |
|-----------|-------------|------|------|-------------|-------|-------|
| 1 (Boot) | 2048 | 512MB | 0x0C | FAT32 | BOOT | Bootable |
| 2 (Active) | Variable | 3584MB | 0x83 | ext4 | rootfs | None |
| 3 (Backup) | Variable | 3584MB | 0x83 | ext4 | rootfs_backup | None |

### Sector Calculations
```
Boot partition start: 2048 (1MB alignment)
Boot partition size: 1048576 sectors (512MB)
Root partition size: 7340032 sectors (3584MB) 
```

### File System Parameters

**FAT32 Boot Partition**:
```bash
mkfs.vfat -F 32 -n "BOOT" /dev/sdX1
```
- **Cluster size**: Auto-selected
- **Reserved sectors**: Default
- **FAT copies**: 2
- **Root directory entries**: Auto-calculated

**ext4 Root Partitions**:
```bash
mkfs.ext4 -F -L "rootfs" /dev/sdX2
mkfs.ext4 -F -L "rootfs_backup" /dev/sdX3
```
- **Block size**: 4KB (default)
- **Inode ratio**: 1 inode per 16KB
- **Reserved blocks**: 5% (default)
- **Features**: All standard ext4 features enabled

## Algorithm Details

### Partition Detection Algorithm
```bash
# Extract partition information from backup image
while IFS= read -r line; do
    if [[ $line =~ ^${backup_image}[0-9]+ ]]; then
        start_sector=$(echo "$line" | awk '{print $2}')
        end_sector=$(echo "$line" | awk '{print $3}')
        sector_count=$(echo "$line" | awk '{print $4}')
        
        # Store partition information
        if [[ $line =~ ${backup_image}1 ]]; then
            BOOT_START=$start_sector
            BOOT_SIZE=$sector_count
        elif [[ $line =~ ${backup_image}2 ]]; then
            ROOT_START=$start_sector
            ROOT_SIZE=$sector_count
        fi
    fi
done < <(fdisk -l "$backup_image" 2>/dev/null)
```

### Data Synchronization Algorithm
```bash
# Mount source partition using loop device
loop_device=$(losetup --show -f -o $((ROOT_START * 512)) "$backup_image")
mount "$loop_device" "$source_mount"

# Sync to both target partitions
rsync -axHAWXS --numeric-ids "$source_mount/" "$active_mount/"
rsync -axHAWXS --numeric-ids "$source_mount/" "$backup_mount/"
```

### Configuration Update Algorithm
```bash
# Update fstab for active partition
sed -i 's|/dev/mmcblk0p[0-9]|/dev/mmcblk0p2|g' "$active_mount/etc/fstab"

# Update fstab for backup partition (pre-configured for activation)
sed -i 's|/dev/mmcblk0p[0-9]|/dev/mmcblk0p3|g' "$backup_mount/etc/fstab"

# Update boot parameters
sed -i 's|root=/dev/mmcblk0p[0-9]|root=/dev/mmcblk0p2|g' "$boot_mount/cmdline.txt"
```

## Error Handling Matrix

| Error Condition | Detection Method | Recovery Action | Exit Code |
|----------------|------------------|-----------------|-----------|
| Not root | `$EUID -ne 0` | Display error, exit | 1 |
| Invalid backup | `fdisk -l` fails | Display error, exit | 1 |
| Device not found | `[[ ! -b "$device" ]]` | Display error, exit | 1 |
| Device mounted | `mount \| grep` | Display error, exit | 1 |
| Insufficient space | Size calculation | Display error, exit | 1 |
| Partition failure | `fdisk` exit code | Cleanup, exit | 1 |
| Format failure | `mkfs.*` exit code | Cleanup, exit | 1 |
| Mount failure | `mount` exit code | Cleanup, exit | 1 |
| Sync failure | `rsync` exit code | Cleanup, exit | 1 |

## Memory and Storage Requirements

### Runtime Memory Usage
- **Base script**: ~10MB
- **Loop device operations**: Minimal
- **rsync operations**: ~50-100MB (depends on file count)
- **Temporary mounts**: Minimal

### Storage Requirements
- **Minimum target device**: 8GB
- **Recommended target device**: 16GB+
- **Temporary space**: None (direct copy operations)

### Performance Characteristics
- **Partition creation**: ~5-10 seconds
- **Format operations**: ~30-60 seconds
- **Boot partition copy**: ~5-15 seconds (depends on device speed)
- **Root partition sync**: ~5-15 minutes (depends on data size and device speed)
- **Total time**: ~6-16 minutes for typical 5GB backup

## Security Model

### Privilege Requirements
- **Script execution**: Root privileges required
- **Device access**: Block device read/write access
- **Loop device management**: Root-only operation
- **Mount operations**: Root-only operation

### Security Boundaries
- **Input validation**: All parameters validated before use
- **Device verification**: Prevents writing to wrong devices
- **Mount point isolation**: Uses temporary directories
- **Cleanup assurance**: Automatic cleanup on exit/error

### Potential Security Risks
- **Data destruction**: Complete device overwrite
- **Privilege escalation**: Requires root access
- **Loop device exhaustion**: Theoretical DoS vector

## Reset System Technical Details

### Reset Script Architecture
```bash
#!/bin/bash
# Embedded reset script template

SAFETY_CHECKS()     # Confirm user intent
MOUNT_MANAGEMENT()  # Handle backup/active mounts  
FILE_SYNC()         # Sync backup to active
CONFIG_UPDATE()     # Fix partition references
CLEANUP()           # Unmount and cleanup
```

### Reset Process Flow
```
User Execution → Safety Confirmation → Mount Backup → Mount Active (bind) → 
Selective Cleanup → rsync Transfer → Config Updates → Cleanup → Reboot Required
```

### Reset Exclusions
Protected directories during reset:
- `/proc` - Process information
- `/sys` - System information  
- `/dev` - Device files
- `/run` - Runtime data
- `/tmp` - Temporary files

## API and Integration Points

### Environment Variables
```bash
SOURCE_DEVICE="/dev/sdb"              # Source for backups
DEFAULT_OUTPUT_DIR="/home/pi/pi-images" # Backup storage
DEFAULT_TARGET_DEVICE="/dev/sdc"       # Default target
BOOT_PARTITION_SIZE="512M"            # Boot partition size
ROOT_PARTITION_SIZE="3584M"           # Root partition size
```

### Exported Functions
The script uses internal functions but exports partition information:
```bash
export BACKUP_BOOT_START="$boot_start"
export BACKUP_BOOT_SIZE="$boot_size" 
export BACKUP_ROOT_START="$root_start"
export BACKUP_ROOT_SIZE="$root_size"
```

### Integration with backup_pi_image.sh
```bash
# Backup creation
backup_pi_image.sh → /home/pi/pi-images/pi-backup-YYYYMMDD-HHMMSS.img

# Disk creation (auto-detects latest backup)
create_pi_disk.sh → uses latest backup automatically

# Reset functionality (on target Pi)
pi-reset.sh → restores from partition 3 to partition 2
```

## Testing Specifications

### Test Categories
1. **Unit Tests**: Individual function validation
2. **Integration Tests**: End-to-end workflow
3. **Error Tests**: Error condition handling
4. **Performance Tests**: Speed and resource usage
5. **Compatibility Tests**: Different Pi models and images

### Test Cases
```
TC001: Valid backup image with default target device
TC002: Custom backup image and target device  
TC003: Compressed backup image handling
TC004: Invalid backup image rejection
TC005: Non-existent target device handling
TC006: Mounted target device detection
TC007: Insufficient space detection
TC008: Reset script functionality
TC009: Configuration file updates
TC010: Cleanup after interruption
```

### Validation Criteria
- **Functional**: All partitions created and populated correctly
- **Bootable**: Target Pi boots successfully from created disk
- **Reset**: Reset functionality works as expected
- **Data Integrity**: No data corruption during copy operations
- **Error Handling**: Graceful failure and cleanup

## Compatibility Matrix

### Raspberry Pi Models
| Model | Boot Compatibility | Root Compatibility | Reset Compatibility |
|-------|-------------------|-------------------|-------------------|
| Pi Zero | ✅ | ✅ | ✅ |
| Pi Zero W | ✅ | ✅ | ✅ |
| Pi 2B | ✅ | ✅ | ✅ |
| Pi 3B | ✅ | ✅ | ✅ |
| Pi 3B+ | ✅ | ✅ | ✅ |
| Pi 4B | ✅ | ✅ | ✅ |
| Pi 400 | ✅ | ✅ | ✅ |

### Operating Systems
| OS | Source Support | Target Support | Reset Support |
|----|---------------|---------------|---------------|
| Raspberry Pi OS Lite | ✅ | ✅ | ✅ |
| Raspberry Pi OS Desktop | ✅ | ✅ | ✅ |
| Ubuntu Server | ✅ | ✅ | ⚠️ |
| Custom builds | ⚠️ | ⚠️ | ⚠️ |

Legend: ✅ Full support, ⚠️ May require modifications

## Maintenance and Updates

### Version Control
- **Configuration changes**: Update DEFAULT_* variables
- **Partition sizes**: Modify SIZE constants  
- **Reset script**: Update embedded script template
- **Error messages**: Centralized in print_* functions

### Monitoring Points
- **Disk space usage**: Monitor /home/pi/pi-images/
- **Device availability**: Track target device usage
- **Performance metrics**: Monitor sync times
- **Error rates**: Track failure conditions

### Update Procedures
1. **Test changes**: Validate on non-production systems
2. **Version bump**: Update version strings
3. **Documentation**: Update all documentation files
4. **Backup compatibility**: Ensure backward compatibility
5. **Deployment**: Roll out to production systems

---

**Document Status**: Complete
**Review Required**: Before production deployment
**Next Review**: As needed for updates or issues