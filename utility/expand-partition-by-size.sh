#!/bin/bash
# Script to expand a partition by a specific amount
# Usage: expand-partition-by-size.sh <device> <partition_number> <size>
# Example: expand-partition-by-size.sh /dev/mmcblk0 3 1GB

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <device> <partition_number> <size>"
    echo "Example: $0 /dev/mmcblk0 3 1GB"
    echo "Size can be specified as: 1GB, 500MB, 2048MB, etc."
    exit 1
fi

DEVICE="$1"
PARTITION_NUM="$2"
SIZE_TO_ADD="$3"

# Handle different device naming conventions
if [[ "$DEVICE" =~ mmcblk|nvme|loop ]]; then
    PARTITION="${DEVICE}p${PARTITION_NUM}"
else
    PARTITION="${DEVICE}${PARTITION_NUM}"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Check if device exists
if [ ! -b "$DEVICE" ]; then
    echo "Device $DEVICE does not exist"
    exit 1
fi

# Check if partition exists
if [ ! -b "$PARTITION" ]; then
    echo "Partition $PARTITION does not exist"
    exit 1
fi

echo "Current partition layout:"
parted "$DEVICE" print

echo
echo "Current filesystem usage:"
if mountpoint -q "$PARTITION" 2>/dev/null; then
    df -h "$PARTITION"
else
    echo "Partition $PARTITION is not mounted"
fi

echo
echo "Will expand partition $PARTITION_NUM by $SIZE_TO_ADD"
read -p "Do you want to continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Operation cancelled."
    exit 0
fi

# Get current end position of the partition
CURRENT_END=$(parted "$DEVICE" unit s print | grep "^ $PARTITION_NUM " | awk '{print $3}' | sed 's/s//')
echo "Current end sector: $CURRENT_END"

# Convert size to sectors (assuming 512 bytes per sector)
case "$SIZE_TO_ADD" in
    *GB)
        GB_SIZE=$(echo "$SIZE_TO_ADD" | sed 's/GB//')
        SECTORS_TO_ADD=$((GB_SIZE * 1024 * 1024 * 1024 / 512))
        ;;
    *MB)
        MB_SIZE=$(echo "$SIZE_TO_ADD" | sed 's/MB//')
        SECTORS_TO_ADD=$((MB_SIZE * 1024 * 1024 / 512))
        ;;
    *)
        echo "Unsupported size format: $SIZE_TO_ADD"
        echo "Please use format like 1GB or 500MB"
        exit 1
        ;;
esac

NEW_END=$((CURRENT_END + SECTORS_TO_ADD))
echo "New end sector will be: $NEW_END"

# Check if there's enough space
DISK_SIZE_SECTORS=$(parted "$DEVICE" unit s print | grep "^Disk" | awk '{print $3}' | sed 's/s//')
echo "Disk size in sectors: $DISK_SIZE_SECTORS"

if [ "$NEW_END" -gt "$DISK_SIZE_SECTORS" ]; then
    echo "Error: Not enough space on disk!"
    echo "Requested end sector: $NEW_END"
    echo "Disk size in sectors: $DISK_SIZE_SECTORS"
    exit 1
fi

echo "Expanding partition $PARTITION_NUM..."
parted "$DEVICE" resizepart "$PARTITION_NUM" "${NEW_END}s"

echo "Expanding filesystem..."
# Detect filesystem type
FS_TYPE=$(blkid -s TYPE -o value "$PARTITION" 2>/dev/null || echo "unknown")

case "$FS_TYPE" in
    ext2|ext3|ext4)
        echo "Detected ext filesystem, checking filesystem first..."
        e2fsck -f "$PARTITION"
        echo "Expanding filesystem with resize2fs..."
        resize2fs "$PARTITION"
        ;;
    xfs)
        echo "Detected XFS filesystem, using xfs_growfs..."
        MOUNT_POINT=$(findmnt -n -o TARGET "$PARTITION" 2>/dev/null || echo "")
        if [ -z "$MOUNT_POINT" ]; then
            echo "XFS partition must be mounted to expand. Please mount it first."
            exit 1
        fi
        xfs_growfs "$MOUNT_POINT"
        ;;
    *)
        echo "Unknown or unsupported filesystem type: $FS_TYPE"
        echo "Please expand the filesystem manually using the appropriate tool."
        exit 1
        ;;
esac

echo
echo "Partition and filesystem expansion complete!"
echo
echo "Updated partition layout:"
parted "$DEVICE" print

echo
echo "Updated filesystem usage:"
if mountpoint -q "$PARTITION" 2>/dev/null; then
    df -h "$PARTITION"
else
    echo "Partition $PARTITION is not mounted"
    echo "Filesystem size: $(tune2fs -l "$PARTITION" 2>/dev/null | grep '^Block count:' | awk '{print $3 * 4096 / 1024 / 1024}') MB"
fi