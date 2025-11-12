# Recovery-Based Reset System Design

## Overview
This document outlines the new 4-partition recovery-based reset system that replaces the reboot-based systemd approach with a dedicated minimal recovery OS.

## Architecture

### Current System (3 partitions)
```
/dev/sdX1 - Boot (FAT32, ~512MB)
/dev/sdX2 - Active Root (ext4, ~3.5GB) 
/dev/sdX3 - Backup Root (ext4, ~3.5GB)
```

### New System (4 partitions)
```
/dev/sdX1 - Boot (FAT32, ~512MB)
/dev/sdX2 - Active Root (ext4, ~3GB)
/dev/sdX3 - Backup Root (ext4, ~3GB) 
/dev/sdX4 - Recovery OS (ext4, ~256MB)
```

## Recovery OS Specifications

### Minimal Linux Distribution
**Option A: Alpine Linux**
- Extremely small footprint (~50MB)
- BusyBox-based utilities
- Built-in support for ext4, FAT32
- Easy to customize

**Option B: Custom BusyBox**
- Even smaller (~20MB)
- Only essential tools included
- Custom init scripts

### Required Tools in Recovery OS
```bash
# Essential system tools
mount, umount, sync
rsync (for restore operation)
mkdir, rm, cp, mv, ln
echo, cat, grep, sed
reboot, halt

# Filesystem tools
e2fsck, fsck.fat
blkid, findmnt

# Basic shell
ash/bash (minimal)

# Network (optional, for debugging)
ping, wget
```

## Boot Selection Mechanism

### Boot Process Flow
```
1. Raspberry Pi boots
2. Bootloader reads /boot/cmdline.txt
3. Check for reset flag file /boot/.pi-reset-scheduled
4. If flag exists:
   - Boot from partition 4 (recovery OS)
   - Recovery OS performs restore
   - Recovery OS removes flag
   - Recovery OS reboots to partition 2 (active)
5. If no flag:
   - Boot normally from partition 2 (active)
```

### Boot Configuration Files

**Normal boot cmdline.txt:**
```
console=serial0,115200 console=tty1 root=PARTUUID=XXXXXXXX-02 rootfstype=ext4 fsck.repair=yes rootwait quiet
```

**Recovery boot cmdline.txt:**
```
console=serial0,115200 console=tty1 root=PARTUUID=XXXXXXXX-04 rootfstype=ext4 fsck.repair=yes rootwait init=/sbin/recovery-init
```

## Reset Process

### User Initiates Reset
```bash
sudo pi-reset.sh
```

### Reset Script Actions
1. Check if backup partition exists
2. Create flag file `/boot/.pi-reset-scheduled`
3. Modify `/boot/cmdline.txt` to point to recovery partition
4. Schedule reboot

### Recovery OS Actions
1. Boot from partition 4
2. Mount active partition (/dev/sdX2)
3. Mount backup partition (/dev/sdX3)
4. Perform rsync restore (backup → active)
5. Remove flag file from boot partition
6. Restore normal cmdline.txt
7. Sync and reboot to active partition

## Implementation Benefits

### Safety
- ✅ No filesystem manipulation on running system
- ✅ Dedicated OS for restore operations
- ✅ Complete isolation between normal and recovery operations
- ✅ No systemd complexity

### Reliability
- ✅ Minimal recovery OS = fewer failure points
- ✅ Known good state for recovery operations
- ✅ Recovery OS never gets modified by normal operations
- ✅ Predictable boot sequence

### Maintainability
- ✅ Clear separation of concerns
- ✅ Recovery OS can be tested independently
- ✅ Simple boot flag mechanism
- ✅ Easy to troubleshoot

## Partition Size Allocation

For 8GB SD card:
```
Partition 1 (Boot):     512MB  (6%)
Partition 2 (Active):   3072MB (38%)
Partition 3 (Backup):   3072MB (38%)
Partition 4 (Recovery): 256MB  (3%)
Free space:             ~1GB   (15%)
```

## Recovery OS File Structure
```
/
├── bin/           # Essential binaries (busybox)
├── sbin/          # System binaries, recovery-init
├── etc/           # Minimal config files
├── mnt/           # Mount points for active/backup
│   ├── active/
│   ├── backup/
│   └── boot/
├── proc/          # Process filesystem
├── sys/           # Sysfs
├── dev/           # Device files
├── tmp/           # Temporary files
└── recovery/      # Recovery scripts and tools
    ├── restore.sh
    ├── verify.sh
    └── utils.sh
```

## Implementation Plan

1. **Design partition layout** - Define exact sizes and types
2. **Build recovery OS** - Alpine Linux or custom BusyBox
3. **Modify create_pi_disk.sh** - Support 4 partitions
4. **Implement boot selection** - cmdline.txt modification
5. **Create recovery scripts** - Restore logic for recovery OS
6. **Update reset script** - Boot flag instead of systemd

## Risk Mitigation

### Boot Corruption Protection
- Keep backup copy of working cmdline.txt
- Recovery OS can restore boot configuration
- Multiple recovery entry points

### Recovery OS Protection
- Read-only mounting when possible
- Minimal modification of recovery partition
- Verification checksums

### Data Protection
- Verify backup partition before restore
- Progress logging during restore
- Rollback capability if restore fails