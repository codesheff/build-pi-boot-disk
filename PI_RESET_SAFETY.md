# Pi Reset Safety Guide

## Problem with Original Reset Script

The original `pi-reset.sh` script had a critical flaw: when run from the system being reset, it would delete essential system binaries (like `rm`, `cd`, `sudo`) before completing the restore process. This left the system in an unusable state.

## Fixed Solutions

### 1. Updated Internal Reset Script

The embedded `pi-reset.sh` script has been improved with:

- **Safer rsync approach**: Uses `rsync --delete` instead of manually deleting files first
- **Preserved system integrity**: Avoids removing essential binaries during the process
- **Better error handling**: More robust mount and unmount procedures
- **Safety warnings**: Warns users about potential risks when running from the target system

**Usage:**
```bash
sudo pi-reset.sh
```

**Limitations:**
- Still risky when run from the system being reset
- System may become temporarily unstable during the process
- Requires physical access to reboot if something goes wrong

### 2. External Reset Script (Recommended)

The new `external_pi_reset.sh` script provides a much safer approach:

- **External operation**: Run from a different system/computer
- **No system disruption**: Target Pi disk is not mounted or in use
- **Complete safety**: No risk of breaking the running system
- **Clean operation**: Guaranteed consistent state after completion

**Usage:**
```bash
# From another Linux system with the Pi disk connected
sudo ./external_pi_reset.sh /dev/sdb  # Replace with actual device
```

## Best Practices

### When to Use Each Method

1. **Use external_pi_reset.sh when:**
   - You have access to another Linux system
   - The Pi disk can be connected as an external drive
   - You want guaranteed safety and reliability
   - The Pi is not currently running or is powered off

2. **Use internal pi-reset.sh when:**
   - You only have access to the Pi itself
   - The Pi is running and you can't easily remove the disk
   - You understand the risks and have physical access for recovery

### Safety Precautions for Internal Reset

If you must use the internal reset script:

1. **Close all applications** and log out other users
2. **Run in single-user mode** for maximum safety:
   ```bash
   sudo telinit 1    # Switch to single-user mode
   sudo pi-reset.sh  # Run the reset
   ```
3. **Have physical access** to power cycle if needed
4. **Backup important data** to another location first
5. **Ensure stable power** (UPS recommended)

### Recovery Procedures

If the internal reset fails:

1. **Power cycle** the system (hard reboot)
2. **Boot from rescue media** (USB/SD card with Linux)
3. **Use external_pi_reset.sh** from the rescue system
4. **Check disk integrity** with `fsck` if needed

## Technical Details

### How the Fix Works

The original problem:
```bash
# OLD APPROACH (BROKEN):
rm -rf /bin /usr /etc ...  # Deletes essential commands
rsync backup/ /          # Tries to restore, but rm/rsync are gone!
```

The fixed approach:
```bash
# NEW APPROACH (SAFE):
rsync --delete backup/ /  # Replaces files atomically
# System binaries remain available until replacement is complete
```

### Filesystem Labels

Both scripts work with the standard dual-partition setup:
- `system-boot` - Boot partition (FAT32) - Partition 1
- `writable_backup` - Backup root partition (ext4) - Partition 2  
- `writable` - Active root partition (ext4) - Partition 3

## Troubleshooting

### "Command not found" errors
- **Cause**: Old version of script deleted system binaries
- **Solution**: Use external reset script or boot from rescue media

### "Cannot mount partition" errors
- **Cause**: Disk is in use or corrupted
- **Solution**: Unmount properly or check disk with `fsck`

### System won't boot after reset
- **Cause**: Incomplete restore or disk corruption
- **Solution**: Re-run external reset script or recreate disk

## Migration Guide

To update existing Pi systems with the fixed reset script:

1. **Update the script** by recreating the disk with the latest `create_pi_disk.sh`
2. **Or manually update** by copying the new script to `/usr/local/bin/pi-reset.sh`
3. **Test carefully** in a non-production environment first

Remember: The external reset script is always the safest option!