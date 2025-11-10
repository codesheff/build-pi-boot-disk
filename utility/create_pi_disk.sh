#!/bin/bash

# Pi Disk Creation Script
# This script creates a Pi disk with dual root partitions from Ubuntu image
# Usage: ./create_pi_disk.sh [ubuntu_image] [target_device]

set -e  # Exit on any error

# Source shared cloud-init functions
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/cloud-init-shared.sh"

# Configuration
DEFAULT_UBUNTU_IMAGE="/home/pi/ubuntu-images/*.img"
DEFAULT_TARGET_DEVICE="/dev/sda"  # Different from source

BOOT_PARTITION_SIZE="512M"
ROOT_PARTITION_SIZE="3584M"  # 3.5GB for each root partition

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to find Ubuntu image
find_ubuntu_image() {
    local image_pattern="$1"
    
    if [[ -f "$image_pattern" ]]; then
        echo "$image_pattern"
        return 0
    fi
    
    # Try to find the latest Ubuntu image
    local latest_image=$(ls -t /home/pi/ubuntu-images/*.img 2>/dev/null | head -1)
    if [[ -f "$latest_image" ]]; then
        echo "$latest_image"
        return 0
    fi
    
    return 1
}

# Function to validate Ubuntu image
validate_ubuntu_image() {
    local ubuntu_image="$1"
    
    if [[ ! -f "$ubuntu_image" ]]; then
        print_error "Ubuntu image not found: $ubuntu_image"
        exit 1
    fi
    
    # Check if it's a valid image (has partition table)
    if ! fdisk -l "$ubuntu_image" &>/dev/null; then
        print_error "Invalid Ubuntu image: $ubuntu_image"
        exit 1
    fi
    
    print_status "Validated Ubuntu image: $ubuntu_image"
    local image_size=$(du -h "$ubuntu_image" | cut -f1)
    print_status "Image size: $image_size"
    
    # Check if it looks like an Ubuntu image
    if fdisk -l "$ubuntu_image" | grep -q "system-boot\|writable"; then
        print_status "Detected Ubuntu Server image format"
    else
        print_warning "Image may not be a standard Ubuntu Server image"
    fi
}

# Function to validate target device
validate_target_device() {
    local target_device="$1"
    
    if [[ ! -b "$target_device" ]]; then
        print_error "Target device not found or not a block device: $target_device"
        exit 1
    fi
    
    # Check if device is mounted
    if mount | grep -q "^$target_device"; then
        print_error "Target device $target_device has mounted partitions"
        print_error "Please unmount all partitions first"
        exit 1
    fi
    
    local device_size=$(blockdev --getsize64 "$target_device")
    local device_size_gb=$((device_size / 1024 / 1024 / 1024))
    
    # Check minimum size (need space for boot + 2 root partitions)
    if [[ $device_size_gb -lt 8 ]]; then
        print_error "Target device too small. Need at least 8GB, found ${device_size_gb}GB"
        exit 1
    fi
    
    print_status "Validated target device: $target_device (${device_size_gb}GB)"
}

# Function to extract partition information from Ubuntu image
analyze_ubuntu_partitions() {
    local ubuntu_image="$1"
    
    print_status "Analyzing Ubuntu image partitions..."
    
    # Get partition information
    local partition_info=$(fdisk -l "$ubuntu_image" 2>/dev/null)
    
    # Extract boot partition info (usually partition 1) - handle bootable flag
    local boot_line=$(echo "$partition_info" | grep "${ubuntu_image}1")
    local boot_start=$(echo "$boot_line" | sed 's/\*//' | awk '{print $2}')
    local boot_end=$(echo "$boot_line" | sed 's/\*//' | awk '{print $3}')
    local boot_size=$(echo "$boot_line" | sed 's/\*//' | awk '{print $4}')
    
    # Extract root partition info (usually partition 2)
    local root_line=$(echo "$partition_info" | grep "${ubuntu_image}2")
    local root_start=$(echo "$root_line" | awk '{print $2}')
    local root_end=$(echo "$root_line" | awk '{print $3}')
    local root_size=$(echo "$root_line" | awk '{print $4}')
    
    print_status "Boot partition: sectors $boot_start-$boot_end ($boot_size sectors)"
    print_status "Root partition: sectors $root_start-$root_end ($root_size sectors)"
    
    # Export for use in other functions
    export UBUNTU_BOOT_START="$boot_start"
    export UBUNTU_BOOT_SIZE="$boot_size"
    export UBUNTU_ROOT_START="$root_start"
    export UBUNTU_ROOT_SIZE="$root_size"
}

# Function to create partition table on target device
create_partition_table() {
    local target_device="$1"
    
    print_status "Creating new partition table on $target_device..."
    
    # Wipe existing partition table
    wipefs -a "$target_device" || true
    
    # Create new DOS partition table and partitions
    fdisk "$target_device" << EOF
o
n
p
1

+${BOOT_PARTITION_SIZE}
t
c
n
p
2

+${ROOT_PARTITION_SIZE}
n
p
3

+${ROOT_PARTITION_SIZE}
a
1
w
EOF

    # Force kernel to re-read partition table
    partprobe "$target_device"
    sleep 2
    
    print_success "Created partition table:"
    print_status "  ${target_device}1: Boot partition (${BOOT_PARTITION_SIZE})"
    print_status "  ${target_device}2: Root partition (backup) (${ROOT_PARTITION_SIZE})"
    print_status "  ${target_device}3: Root partition (active) (${ROOT_PARTITION_SIZE})"
}

# Function to format partitions
format_partitions() {
    local target_device="$1"
    
    print_status "Formatting partitions..."
    
    # Format boot partition as FAT32 with correct label for Ubuntu
    mkfs.vfat -F 32 -n "system-boot" "${target_device}1"
    
    # Format root partitions as ext4 with correct labels for Ubuntu
    mkfs.ext4 -F -L "writable_backup" "${target_device}2"
    mkfs.ext4 -F -L "writable" "${target_device}3"
    
    print_success "Partitions formatted successfully"
}

# Function to generate cloud-init files using shared function
generate_cloud_init_files() {
    local target_device="$1"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local cloud_init_files_dir="$script_dir/../cloud-init-files"
    
    print_status "Applying cloud-init configuration..."
    # Use the shared function to apply cloud-init files to the boot partition
    apply_cloud_init_files "${target_device}1" "$cloud_init_files_dir"
}

# Function to copy boot partition
copy_boot_partition() {
    local ubuntu_image="$1"
    local target_device="$2"
    
    print_status "Copying boot partition..."
    
    # Extract and copy boot partition
    dd if="$ubuntu_image" of="${target_device}1" bs=512 skip="$UBUNTU_BOOT_START" count="$UBUNTU_BOOT_SIZE" status=progress
    
    print_success "Boot partition copied successfully"
}

# Function to copy root partition to both active and backup
copy_root_partitions() {
    local ubuntu_image="$1"
    local target_device="$2"
    
    print_status "Copying root partition to active partition (${target_device}3)..."
    
    # Create temporary mount points
    local temp_dir=$(mktemp -d)
    local mount_source="$temp_dir/source"
    local mount_active="$temp_dir/active"
    local mount_backup_part="$temp_dir/backup_part"
    
    mkdir -p "$mount_source" "$mount_active" "$mount_backup_part"
    
    # Mount the Ubuntu image root partition using kpartx for better compatibility
    print_status "Setting up loop device for Ubuntu image..."
    local loop_mappings=$(kpartx -av "$ubuntu_image")
    local loop_device=$(echo "$loop_mappings" | head -1 | awk '{print $3}' | sed 's/p[0-9]*$//')
    
    sleep 2  # Wait for device mapper to be ready
    
    # Find the root partition device
    local root_partition_device=""
    if [[ -b "/dev/mapper/${loop_device}p2" ]]; then
        root_partition_device="/dev/mapper/${loop_device}p2"
    else
        print_error "Could not find root partition in Ubuntu image"
        kpartx -d "$ubuntu_image" 2>/dev/null || true
        exit 1
    fi
    
    # Mount the source root partition
    if ! mount "$root_partition_device" "$mount_source"; then
        print_error "Failed to mount Ubuntu image root partition"
        kpartx -d "$ubuntu_image" 2>/dev/null || true
        exit 1
    fi
    
    print_status "Successfully mounted Ubuntu root partition"
    
    # Mount target partitions
    mount "${target_device}3" "$mount_active"
    mount "${target_device}2" "$mount_backup_part"
    
    # Copy files to active partition
    print_status "Copying files to active root partition..."
    rsync -axHAWXS --numeric-ids "$mount_source/" "$mount_active/"
    
    # Copy files to backup partition
    print_status "Copying files to backup root partition..."
    rsync -axHAWXS --numeric-ids "$mount_source/" "$mount_backup_part/"
    
    # Note: System customizations are now handled by cloud-init during first boot
    print_status "System configuration will be applied by cloud-init during first boot"
    
    # Update fstab files (Ubuntu uses LABELs, so keep them consistent)
    print_status "Updating fstab files..."
    
    # Ensure both partitions use the correct LABEL format for Ubuntu
    # Active partition fstab - uses 'writable' label (matches our partition label)
    if [[ -f "$mount_active/etc/fstab" ]]; then
        # Make sure it uses the right labels
        sed -i 's|LABEL=rootfs|LABEL=writable|g' "$mount_active/etc/fstab" 2>/dev/null || true
        sed -i 's|LABEL=BOOT|LABEL=system-boot|g' "$mount_active/etc/fstab" 2>/dev/null || true
    fi
    
    # Backup partition fstab - also uses 'writable' label (for when it becomes active)
    if [[ -f "$mount_backup_part/etc/fstab" ]]; then
        # Make sure it uses the right labels
        sed -i 's|LABEL=rootfs|LABEL=writable|g' "$mount_backup_part/etc/fstab" 2>/dev/null || true
        sed -i 's|LABEL=BOOT|LABEL=system-boot|g' "$mount_backup_part/etc/fstab" 2>/dev/null || true
    fi
    
    # Update cmdline.txt if it exists (though Ubuntu cloud-init may not use it)
    if [[ -f "$mount_active/boot/cmdline.txt" ]]; then
        sed -i 's|root=/dev/mmcblk0p[0-9]*|root=LABEL=writable|g' "$mount_active/boot/cmdline.txt" 2>/dev/null || true
    fi
    
    # Cleanup
    umount "$mount_source" "$mount_active" "$mount_backup_part" 2>/dev/null || true
    kpartx -d "$ubuntu_image" 2>/dev/null || true
    rm -rf "$temp_dir"
    
    print_success "Root partitions copied successfully"
}



# Function to create reset script on the target device
create_reset_script() {
    local target_device="$1"
    
    print_status "Creating reset script on target device..."
    
    # Mount the active root partition temporarily
    local temp_mount=$(mktemp -d)
    mount "${target_device}3" "$temp_mount"
    
    # Create the reset script
    cat > "$temp_mount/usr/local/bin/pi-reset.sh" << 'EOF'
#!/bin/bash

# Pi Reset Script
# This script resets the active root partition (partition 3) from the backup partition (partition 2)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check for required dependencies before doing anything destructive
print_status "Checking required dependencies..."

# List of required commands
REQUIRED_COMMANDS=("rsync" "mount" "umount" "find" "mktemp" "rm")
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [[ ${#MISSING_COMMANDS[@]} -gt 0 ]]; then
    print_error "Missing required dependencies:"
    printf '  - %s\n' "${MISSING_COMMANDS[@]}"
    print_error "Please install the missing commands before running this script"
    print_status "On Ubuntu/Debian: sudo apt-get install rsync coreutils util-linux"
    exit 1
fi

# Check if backup partition exists and is accessible
print_success "All dependencies verified"

# Check if backup partition exists and is accessible
if ! findmnt LABEL=writable_backup &>/dev/null && ! blkid -L writable_backup &>/dev/null; then
    print_error "Backup partition (LABEL=writable_backup) not found"
    print_error "This system may not have been created with the dual-partition setup"
    exit 1
fi

# Safety check: Detect if we're running from the filesystem we're about to reset
CURRENT_ROOT_LABEL=$(findmnt -n -o LABEL /)
if [[ "$CURRENT_ROOT_LABEL" == "writable" ]]; then
    print_warning "DETECTED: Running from the partition that will be reset!"
    print_warning "This is potentially dangerous. Consider one of these safer alternatives:"
    print_warning "  1. Boot from a USB/SD card rescue system"
    print_warning "  2. Run from single-user mode (init=/bin/bash)"
    print_warning "  3. Use 'telinit 1' to switch to single-user mode first"
    print_warning ""
    print_warning "If the reset fails partway through, you may need to power cycle"
    print_warning "the system to recover."
    print_warning ""
fi

print_success "All dependencies verified"

print_warning "This will reset the active root partition to its original state!"
print_warning "All changes made to the system will be lost!"
print_warning ""
print_warning "IMPORTANT: During the reset process, the system may become temporarily"
print_warning "unstable as files are being replaced. It's recommended to:"
print_warning "  1. Close all non-essential applications"
print_warning "  2. Ensure no other users are logged in"
print_warning "  3. Have physical access to reboot if needed"
print_warning ""
read -p "Are you sure you want to continue? (yes/NO): " -r

if [[ "$REPLY" != "yes" ]]; then
    print_status "Reset cancelled"
    exit 0
fi

print_status "Starting system reset..."

# Create temporary mount points
TEMP_DIR=$(mktemp -d)
BACKUP_MOUNT="$TEMP_DIR/backup"
ACTIVE_MOUNT="$TEMP_DIR/active"

# Set up cleanup trap to ensure mounts are cleaned up on exit/interrupt
cleanup_on_exit() {
    print_status "Cleaning up on exit..."
    umount "$BACKUP_MOUNT" 2>/dev/null || true
    umount "$ACTIVE_MOUNT" 2>/dev/null || true
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup_on_exit EXIT INT TERM

mkdir -p "$BACKUP_MOUNT" "$ACTIVE_MOUNT"

# Mount backup partition using label (more reliable than device path)
print_status "Mounting backup partition..."
if ! mount LABEL=writable_backup "$BACKUP_MOUNT"; then
    print_error "Failed to mount backup partition (LABEL=writable_backup)"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Verify backup partition has expected content
if [[ ! -d "$BACKUP_MOUNT/etc" ]] || [[ ! -d "$BACKUP_MOUNT/usr" ]] || [[ ! -d "$BACKUP_MOUNT/var" ]]; then
    print_error "Backup partition does not contain expected system directories"
    print_error "The backup may be corrupted or incomplete"
    umount "$BACKUP_MOUNT" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Mount active partition directly using the device label
print_status "Preparing active partition for reset..."
if ! mount LABEL=writable "$ACTIVE_MOUNT"; then
    print_error "Failed to mount active partition (LABEL=writable)"
    umount "$BACKUP_MOUNT" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit 1
fi

print_status "Restoring system from backup (this may take several minutes)..."

# Use rsync with --delete to safely replace the filesystem
# This approach avoids deleting everything first, which would break the running script
if ! rsync -axHAWXS --numeric-ids --delete \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/run \
    --exclude=/tmp \
    --exclude="$TEMP_DIR" \
    --exclude=/usr/local/bin/pi-reset.sh \
    --exclude=/usr/local/bin/reset-pi \
    "$BACKUP_MOUNT/" "$ACTIVE_MOUNT/"; then
    print_error "Failed to restore system from backup"
    print_error "System may be in an inconsistent state - reboot recommended"
    exit 1
fi

# Restore the reset script (in case it was different in backup)
print_status "Ensuring reset script is available after restore..."
if [[ -f "$BACKUP_MOUNT/usr/local/bin/pi-reset.sh" ]]; then
    cp "$BACKUP_MOUNT/usr/local/bin/pi-reset.sh" "$ACTIVE_MOUNT/usr/local/bin/" 2>/dev/null || true
    chmod +x "$ACTIVE_MOUNT/usr/local/bin/pi-reset.sh" 2>/dev/null || true
    ln -sf /usr/local/bin/pi-reset.sh "$ACTIVE_MOUNT/usr/local/bin/reset-pi" 2>/dev/null || true
fi

# Fix fstab (ensure it uses the right labels - should already be correct)
print_status "Updating system configuration..."
sed -i 's|LABEL=writable_backup|LABEL=writable|g' "$ACTIVE_MOUNT/etc/fstab" 2>/dev/null || true

# Verify critical system files exist after restore
if [[ ! -f "$ACTIVE_MOUNT/etc/fstab" ]] || [[ ! -f "$ACTIVE_MOUNT/etc/passwd" ]]; then
    print_error "Critical system files missing after restore"
    print_error "System may be corrupted - manual intervention required"
    umount "$BACKUP_MOUNT" "$ACTIVE_MOUNT" 2>/dev/null || true
    rm -rf "$TEMP_DIR"
    exit 1
fi

print_success "System reset completed successfully!"
print_status "System restored from backup partition"

# Final verification
RESTORED_SIZE=$(du -sb "$ACTIVE_MOUNT" 2>/dev/null | cut -f1 || echo "0")
if [[ "$RESTORED_SIZE" -lt 100000000 ]]; then  # Less than 100MB suggests failure
    print_warning "Restored system appears smaller than expected"
    print_warning "Please verify system integrity after reboot"
fi

print_warning "Please reboot the system now to complete the reset"
print_status "After reboot, the system will be restored to its original state"

# Cleanup will be handled by the EXIT trap
EOF

    chmod +x "$temp_mount/usr/local/bin/pi-reset.sh"
    
    # Create a convenient symlink
    ln -sf /usr/local/bin/pi-reset.sh "$temp_mount/usr/local/bin/reset-pi" 2>/dev/null || true
    
    # Also install the reset script on the backup partition
    print_status "Installing reset script on backup partition..."
    local backup_mount=$(mktemp -d)
    mount "${target_device}2" "$backup_mount"
    
    # Copy the reset script to backup partition
    cp "$temp_mount/usr/local/bin/pi-reset.sh" "$backup_mount/usr/local/bin/"
    chmod +x "$backup_mount/usr/local/bin/pi-reset.sh"
    ln -sf /usr/local/bin/pi-reset.sh "$backup_mount/usr/local/bin/reset-pi" 2>/dev/null || true
    
    umount "$backup_mount"
    rm -rf "$backup_mount"
    
    umount "$temp_mount"
    rm -rf "$temp_mount"
    
    print_success "Reset script installed on both active and backup partitions"
}

# Function to display final information
display_final_info() {
    local target_device="$1"
    local backup_image="$2"
    
    print_success "Pi disk creation completed successfully!"
    echo
    print_status "Disk Layout:"
    echo "  Device: $target_device"
    echo "  Partition 1: Boot partition (FAT32)"
    echo "  Partition 2: Backup root partition (ext4)"  
    echo "  Partition 3: Active root partition (ext4)"
    echo
    print_status "Usage:"
    echo "  - Insert the disk into a Raspberry Pi and boot normally"
    echo "  - The system will boot from partition 3 (active root)"
    echo "  - To reset the system: sudo pi-reset.sh or sudo reset-pi"
    echo "  - The reset script will restore partition 3 from partition 2"
    echo "  - Compatible with Ubuntu Server and Raspberry Pi OS images"
    echo
    print_status "Source: $backup_image"
    print_status "Created: $(date)"
}

# Main function
main() {
    local ubuntu_image="${1:-}"
    local target_device="${2:-$DEFAULT_TARGET_DEVICE}"
    
    print_status "Pi Disk Creation Script Starting..."
    
    # Pre-flight checks
    check_root
    
    # Find Ubuntu image if not specified
    if [[ -z "$ubuntu_image" ]]; then
        print_status "No Ubuntu image specified, looking for latest..."
        ubuntu_image=$(find_ubuntu_image "$DEFAULT_UBUNTU_IMAGE") || {
            print_error "No Ubuntu image found in /home/pi/ubuntu-images/"
            print_error "Please run download_ubuntu_image.sh first or specify an image file"
            exit 1
        }
        print_status "Using Ubuntu image: $ubuntu_image"
    fi
    
    # Cloud-init configuration will handle all system setup
    print_status "System will be configured via cloud-init during first boot"
    print_status "Customize via cloud-init-templates/secrets.env if needed"
    
    # Validate inputs
    validate_ubuntu_image "$ubuntu_image"
    validate_target_device "$target_device"
    
    # Analyze Ubuntu image
    analyze_ubuntu_partitions "$ubuntu_image"
    
    # Final confirmation
    echo
    print_warning "About to create Pi disk on $target_device"
    print_warning "This will DESTROY ALL DATA on $target_device"
    print_status "Source image: $ubuntu_image"
    print_status "Target device: $target_device"
    print_status "Configuration: cloud-init templates will handle system setup"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled by user"
        exit 0
    fi
    
    # Create the disk
    create_partition_table "$target_device"
    format_partitions "$target_device"
    copy_boot_partition "$ubuntu_image" "$target_device"
    generate_cloud_init_files "$target_device"
    copy_root_partitions "$ubuntu_image" "$target_device"
    create_reset_script "$target_device"
    
    # Display final information
    display_final_info "$target_device" "$ubuntu_image"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [UBUNTU_IMAGE] [TARGET_DEVICE]"
    echo ""
    echo "Arguments:"
    echo "  UBUNTU_IMAGE        Path to Ubuntu image (default: latest in /home/pi/ubuntu-images/)"
    echo "  TARGET_DEVICE       Target device to write to (default: $DEFAULT_TARGET_DEVICE)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use latest image, default device"
    echo "  $0 /path/to/ubuntu.img               # Use specific image, default device"
    echo "  $0 /path/to/ubuntu.img /dev/sdc      # Specify image and device"
    echo ""
    echo "The script creates a disk with:"
    echo "  - Boot partition (FAT32) with cloud-init configuration"
    echo "  - Backup root partition (ext4) - for system reset"
    echo "  - Active root partition (ext4)"
    echo ""
    echo "Configuration:"
    echo "  - System setup handled by cloud-init during first boot"
    echo "  - Customize via cloud-init-templates/secrets.env"
    echo "  - Generate cloud-init files with: cd cloud-init-templates && ./generate-cloud-init-files.sh"
    echo ""
    echo "Required tools:"
    echo "  - download_ubuntu_image.sh  (to get Ubuntu images)"
    echo "  - cloud-init-templates/     (to configure system via cloud-init)"
    echo ""
    echo "Note: This script must be run as root (use sudo)"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function with all arguments
main "$@"