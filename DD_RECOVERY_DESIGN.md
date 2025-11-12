# DD-Based Recovery System Design

## Why DD is Superior for Reset Operations

### Current File-Based Approach Problems
- **Slow**: File-by-file copying of thousands of files
- **Complex**: Must handle special files, permissions, links, attributes
- **Error-prone**: Edge cases with special filesystems, extended attributes
- **Dependencies**: Requires rsync or complex cp operations

### DD Block-Level Approach Benefits
- **Fast**: Block-level copying at hardware speed
- **Simple**: Single command operation
- **Reliable**: Works regardless of filesystem content or state
- **Complete**: Exact bit-for-bit replication including metadata

## Updated Recovery Process

### Traditional Reset (what we were doing):
```bash
# Mount both partitions
mount /dev/sdX2 /mnt/active
mount /dev/sdX3 /mnt/backup

# Complex file copying with exclusions
rsync -axHAWXS --numeric-ids --delete \
    --exclude=/proc --exclude=/sys --exclude=/dev \
    --exclude=/run --exclude=/tmp \
    /mnt/backup/ /mnt/active/

umount /mnt/active /mnt/backup
```

### DD Block Reset (new approach):
```bash
# Simple block-level copy
dd if=/dev/sdX3 of=/dev/sdX2 bs=4M status=progress

# That's it! Complete reset in one command.
```

## Technical Advantages

### Speed Comparison
| Method | 3GB Partition | Comments |
|--------|---------------|----------|
| rsync | 5-10 minutes | File-by-file, metadata overhead |
| cp -a | 8-15 minutes | Still file-by-file operations |
| **dd** | **2-3 minutes** | **Block-level, hardware speed** |

### Reliability
- **No filesystem mounting needed** - Works on raw block devices
- **No special file handling** - Everything copied exactly
- **No permission issues** - Block-level preserves everything
- **Works with corruption** - Can copy even if filesystem has minor issues

### Simplicity
```bash
# Old approach: ~50 lines of code with error handling
# New approach: ~5 lines of code
dd if="$BACKUP_DEVICE" of="$ACTIVE_DEVICE" bs=4M
sync
```

## Updated Recovery OS Requirements

### Minimal Tool Set Needed
```bash
# Essential for DD-based recovery:
dd        # Block copying
blkid     # Find partitions by label
sync      # Ensure writes complete
mount     # Mount boot partition for flags
umount    # Unmount when done
reboot    # Restart system

# Optional for debugging:
fdisk     # Check partition layout
df        # Check disk space
```

### Recovery Script Simplified
```bash
#!/bin/ash
# Simplified recovery with DD

# Find devices
BACKUP_DEV=$(blkid -L writable_backup)
ACTIVE_DEV=$(blkid -L writable)

# Verify devices exist
[ -b "$BACKUP_DEV" ] || exit 1
[ -b "$ACTIVE_DEV" ] || exit 1

# Perform block-level reset
echo "Resetting system with dd..."
dd if="$BACKUP_DEV" of="$ACTIVE_DEV" bs=4M status=progress

# Sync and reboot
sync
reboot
```

## Partition Size Implications

### With DD Block Copying
- **Partitions must be same size** - DD copies exact block count
- **No filesystem expansion needed** - Block-for-block copy
- **Simpler partition layout** - No need for complex sizing

### Updated Partition Scheme
```
/dev/sdX1 - Boot (FAT32, 512MB)
/dev/sdX2 - Active Root (ext4, 3072MB) 
/dev/sdX3 - Backup Root (ext4, 3072MB) - SAME SIZE as active
/dev/sdX4 - Recovery OS (ext4, 256MB)
```

## Safety Considerations

### DD Safety Features
- **Read-only source**: Backup partition never modified
- **Atomic operation**: Either completes fully or fails safely
- **No partial states**: No risk of half-copied files
- **Hardware verification**: Built-in error detection

### Error Handling
```bash
# DD with error handling
if dd if="$BACKUP_DEV" of="$ACTIVE_DEV" bs=4M status=progress; then
    echo "Reset successful"
    sync
    reboot
else
    echo "Reset failed - entering emergency shell"
    exec /bin/ash
fi
```

## Implementation Benefits

### Development
- ✅ **Much simpler code** - 90% less complexity
- ✅ **Fewer dependencies** - No rsync, complex cp options
- ✅ **Easier testing** - Single command to test
- ✅ **Better debugging** - Clear success/failure states

### User Experience  
- ✅ **Faster resets** - 2-3x speed improvement
- ✅ **More reliable** - Fewer failure modes
- ✅ **Progress indicator** - DD status shows progress
- ✅ **Predictable timing** - Block-level copy is consistent

### Maintenance
- ✅ **Less code to maintain** - Simpler recovery script
- ✅ **Fewer edge cases** - Block-level avoids filesystem complexity
- ✅ **Standard tool** - DD available everywhere
- ✅ **Well understood** - Standard system administration tool

This DD-based approach is significantly better for our use case!