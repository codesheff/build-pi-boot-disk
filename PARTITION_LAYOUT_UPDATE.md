# Partition Layout Update

## Change Summary

The partition layout has been updated to improve future disk management capabilities. The active and backup partitions have been swapped.

## New Partition Layout

| Partition | Label | Size | Purpose | Filesystem |
|-----------|-------|------|---------|------------|
| 1 | `system-boot` | 512MB | Boot partition | FAT32 |
| 2 | `writable_backup` | 3.5GB | Backup root partition | ext4 |
| 3 | `writable` | 3.5GB | Active root partition | ext4 |

## Previous Layout (for reference)

| Partition | Label | Size | Purpose | Filesystem |
|-----------|-------|------|---------|------------|
| 1 | `system-boot` | 512MB | Boot partition | FAT32 |
| 2 | `writable` | 3.5GB | Active root partition | ext4 |
| 3 | `writable_backup` | 3.5GB | Backup root partition | ext4 |

## Benefits of New Layout

### 1. **Easier Partition Resizing**
- The active partition (3) is now the last partition on the disk
- Can easily extend partition 3 to use remaining disk space
- No need to move other partitions when resizing

### 2. **Standard Linux Practice**
- Follows common Linux convention of putting variable/growing partitions last
- Allows for future expansion without complex partition management

### 3. **Disk Utility Compatibility**
- Most disk utilities expect the last partition to be resizable
- Tools like `parted`, `fdisk`, and `resize2fs` work more reliably

## Usage Examples

### Expanding the Active Partition
```bash
# After connecting a larger disk or wanting to use unused space
sudo parted /dev/sda resizepart 3 100%  # Expand partition to fill disk
sudo resize2fs /dev/sda3                # Expand filesystem to fill partition
```

### Reset Operations
```bash
# Internal reset (from Pi itself)
sudo pi-reset.sh

# External reset (from another system)
sudo ./external_pi_reset.sh /dev/sda
```

## Compatibility

### Scripts Updated
- ✅ `create_pi_disk.sh` - Updated to create new layout
- ✅ `external_pi_reset.sh` - Updated to work with new layout  
- ✅ `pi-reset.sh` (embedded) - Updated partition references
- ✅ `PI_RESET_SAFETY.md` - Updated documentation

### Filesystem Labels
- Labels remain the same (`system-boot`, `writable`, `writable_backup`)
- Only partition numbers have changed
- Existing reset scripts will continue to work via labels

## Migration

### For New Deployments
- Simply use the updated `create_pi_disk.sh` script
- New disks will automatically use the improved layout

### For Existing Disks
- Existing disks will continue to work with old layout
- To upgrade: backup data, recreate disk with new script, restore data
- Or continue using existing layout (both are supported)

## Technical Details

### Boot Process
- Boot process remains unchanged (always uses partition 1)
- Root filesystem selection via `LABEL=writable` (unchanged)
- Reset process via `LABEL=writable_backup` (unchanged)

### Reset Process
- Active partition (3) ← restored from ← Backup partition (2)
- All reset scripts updated to use correct partition numbers
- Label-based mounting ensures compatibility

This change provides better future-proofing while maintaining full backward compatibility through filesystem labels.