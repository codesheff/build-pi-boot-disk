# Cloud-Init Files Directory

This directory contains the reference cloud-init files that are used by the `recreate-cloud-init.sh` script.

## Contents

- `user-data` - Cloud-init user configuration (copied from /dev/mmcblk0p1)
- `meta-data` - Cloud-init metadata (copied from /dev/mmcblk0p1)  
- `network-config` - Network configuration (copied from /dev/mmcblk0p1)
- `cmdline.txt` - Boot command line parameters (copied from /dev/mmcblk0p1)

## Usage

The `recreate-cloud-init.sh` script now uses these files as the source for recreation instead of generating from templates. This ensures consistency by copying the exact configuration from the current system.

## Updating Reference Files

To update the reference files with current system configuration:

```bash
# Copy from current boot partition
sudo cp /boot/firmware/user-data cloud-init-files/
sudo cp /boot/firmware/meta-data cloud-init-files/
sudo cp /boot/firmware/network-config cloud-init-files/
sudo cp /boot/firmware/cmdline.txt cloud-init-files/

# Fix permissions
sudo chown pi:pi cloud-init-files/*
```

## How It Works

1. The recreate script copies these files directly to the target partition
2. No template processing or variable substitution is performed
3. This ensures identical configuration across all partitions
4. Files are copied exactly as-is from this reference directory

This approach simplifies the recreation process and guarantees consistency.