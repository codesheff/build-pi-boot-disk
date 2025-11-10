# Recreating Cloud-Init Files on Existing Partitions

This document explains how to use the `recreate-cloud-init.sh` script to update cloud-init configuration files on existing boot partitions without recreating the entire disk.

## Overview

The `recreate-cloud-init.sh` script allows you to:
- Update cloud-init files on existing Pi boot partitions
- Change hostnames, usernames, and other configurations
- Backup existing files before making changes
- Preview changes with dry-run mode
- Work with both block devices and mounted filesystems

## Usage

### Basic Syntax
```bash
./recreate-cloud-init.sh [OPTIONS] TARGET_PARTITION [HOSTNAME] [USERNAME]
```

### Arguments
- **TARGET_PARTITION**: Boot partition to update (e.g., `/dev/sda1`, `/mnt/boot`)
- **HOSTNAME**: System hostname (optional, uses secrets.sh default)
- **USERNAME**: User account name (optional, uses secrets.sh default)

### Options
- `--templates-dir DIR`: Path to cloud-init templates directory
- `--backup`: Create backup of existing files before updating
- `--dry-run`: Show what would be done without making changes
- `--force`: Overwrite existing files without confirmation
- `--help`, `-h`: Show help information

## Examples

### 1. Update Boot Partition with Default Settings
```bash
sudo ./recreate-cloud-init.sh /dev/sda1
```
This will:
- Mount `/dev/sda1` temporarily
- Generate new cloud-init files using settings from `secrets.sh`
- Ask for confirmation before overwriting

### 2. Update with Custom Hostname and Username
```bash
sudo ./recreate-cloud-init.sh /dev/sda1 mypi customuser
```
This overrides the default hostname and username from configuration.

### 3. Preview Changes (Dry Run)
```bash
./recreate-cloud-init.sh --dry-run /dev/sda1
```
Shows what files would be generated without making any changes.

### 4. Update with Backup
```bash
sudo ./recreate-cloud-init.sh --backup /dev/sda1
```
Creates a timestamped backup of existing cloud-init files before updating.

### 5. Update Already Mounted Partition
```bash
sudo ./recreate-cloud-init.sh /mnt/boot
```
Works with directories/mount points as well as block devices.

### 6. Force Update Without Confirmation
```bash
sudo ./recreate-cloud-init.sh --force /dev/sda1 newpi
```
Updates files without asking for confirmation.

## What the Script Does

### 1. **Validation Phase**
- Checks if the target partition exists and is accessible
- Validates that cloud-init templates directory exists
- Sources configuration from `config.sh` and `secrets.sh`
- Runs secrets validation (if available)

### 2. **Mounting Phase**
- Automatically mounts block devices to temporary directories
- Works with already-mounted filesystems
- Tracks mount state for proper cleanup

### 3. **Backup Phase** (if `--backup` specified)
- Creates timestamped backup directory on the partition
- Backs up existing `user-data`, `meta-data`, `network-config`, and `cmdline.txt`
- Reports number of files backed up

### 4. **Generation Phase**
- Generates new cloud-init files from templates
- Uses hostname/username from parameters or defaults from secrets
- Preserves or creates `cmdline.txt` as needed
- Handles Ubuntu image structure (current/ subdirectory)

### 5. **Cleanup Phase**
- Unmounts temporarily mounted partitions
- Removes temporary directories
- Reports success or failure

## Files Modified

The script updates these cloud-init files:
- **user-data**: User account, SSH keys, hostname, packages
- **meta-data**: Instance metadata and hostname
- **network-config**: Network configuration including WiFi
- **cmdline.txt**: Boot command line (preserved or created)

## Security Features

### Integration with Secrets System
The script automatically:
- Sources `secrets.sh` for sensitive configuration
- Uses secure password hashes and SSH keys from secrets
- Validates secrets configuration before proceeding
- Warns about default or example credentials

### File Permissions
- Respects existing file permissions on the partition
- Uses sudo for mounting and file operations
- Maintains security of sensitive data during generation

## Error Handling

The script includes comprehensive error handling:
- **Mount failures**: Clear error messages for unmountable partitions
- **Permission errors**: Guidance on using sudo when needed
- **Missing templates**: Validation of template directory structure
- **Invalid partitions**: Checks for valid block devices or directories

## Common Use Cases

### 1. **Updating Existing Pi Configuration**
When you need to change settings on a Pi that's already been imaged:
```bash
sudo ./recreate-cloud-init.sh --backup /dev/sda1 new-hostname
```

### 2. **Mass Configuration Updates**
When updating multiple SD cards with the same configuration:
```bash
for device in /dev/sd{a,b,c}1; do
    sudo ./recreate-cloud-init.sh --force "$device"
done
```

### 3. **Testing Configuration Changes**
Before applying changes, preview them:
```bash
./recreate-cloud-init.sh --dry-run /dev/sda1 test-hostname
```

### 4. **Recovery from Bad Configuration**
If cloud-init configuration is broken, restore from backup and recreate:
```bash
sudo ./recreate-cloud-init.sh --backup /dev/sda1
```

## Integration with Existing Tools

### Works with Secrets System
- Automatically uses credentials from `secrets.sh`
- Respects WiFi configuration from secrets
- Validates security settings before proceeding

### Compatible with Comparison Tools
- Generated files can be compared using `compare-cloud-init.sh`
- Maintains compatibility with existing cloud-init structure

### Complements Disk Creation
- Can update disks created with `create_pi_disk.sh`
- Uses same templates and configuration system
- Preserves all non-cloud-init boot files

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Solution: Use sudo for block device operations
   sudo ./recreate-cloud-init.sh /dev/sda1
   ```

2. **Device Busy**
   ```bash
   # Solution: Unmount the device first
   sudo umount /dev/sda1
   sudo ./recreate-cloud-init.sh /dev/sda1
   ```

3. **Templates Not Found**
   ```bash
   # Solution: Specify templates directory
   ./recreate-cloud-init.sh --templates-dir /path/to/templates /dev/sda1
   ```

4. **Secrets Not Configured**
   ```bash
   # Solution: Set up secrets first
   cd cloud-init-templates
   cp secrets.sh.template secrets.sh
   # Edit secrets.sh with your configuration
   ```

### Verification

After running the script, verify the changes:
```bash
# Compare with original configuration
./compare-cloud-init.sh /dev/sda1 /dev/sdb1

# Check generated files
sudo mount /dev/sda1 /mnt/test
ls -la /mnt/test/{user-data,meta-data,network-config,cmdline.txt}
sudo umount /mnt/test
```

## Best Practices

1. **Always backup** when updating production systems:
   ```bash
   sudo ./recreate-cloud-init.sh --backup /dev/sda1
   ```

2. **Test with dry-run** before applying changes:
   ```bash
   ./recreate-cloud-init.sh --dry-run /dev/sda1 new-config
   ```

3. **Validate secrets** before mass updates:
   ```bash
   cd cloud-init-templates
   ./configure-wifi.sh show-secrets
   ```

4. **Use version control** for template changes:
   ```bash
   git add cloud-init-templates/
   git commit -m "Updated cloud-init templates"
   ```

This script provides a safe, flexible way to update cloud-init configurations on existing Pi boot partitions while maintaining all the security and validation features of the existing system.