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

# Pi Reset Script - Reboot-Based Implementation
# This script schedules a system reset to happen on next boot, avoiding
# issues with manipulating mounted filesystems during operation

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

# Configuration
RESET_FLAG_FILE="/tmp/.pi-reset-scheduled"
SYSTEMD_SERVICE_PATH="/etc/systemd/system/pi-reset-boot.service"
RESET_SCRIPT_PATH="/usr/local/bin/pi-reset-boot.sh"

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check for --status flag
if [[ "$1" == "--status" ]]; then
    if [[ -f "$RESET_FLAG_FILE" ]]; then
        print_warning "System reset is SCHEDULED for next boot"
        print_status "Flag file: $RESET_FLAG_FILE"
        if [[ -f "$SYSTEMD_SERVICE_PATH" ]]; then
            print_status "Reset service: INSTALLED"
        else
            print_error "Reset service: MISSING (installation may have failed)"
        fi
    else
        print_success "No system reset scheduled"
    fi
    exit 0
fi

# Check for --cancel flag
if [[ "$1" == "--cancel" ]]; then
    if [[ -f "$RESET_FLAG_FILE" ]]; then
        rm -f "$RESET_FLAG_FILE"
        systemctl disable pi-reset-boot.service 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE_PATH"
        rm -f "$RESET_SCRIPT_PATH"
        systemctl daemon-reload 2>/dev/null || true
        print_success "System reset cancelled"
        print_status "Removed reset flag and service files"
    else
        print_status "No system reset was scheduled"
    fi
    exit 0
fi

# Main reset scheduling logic
print_status "Pi Reset Script - Reboot-Based Reset"
print_status "This script will schedule a reset to occur on the next boot"
print_status ""

# Check if backup partition exists and is accessible
if ! blkid -L writable_backup &>/dev/null; then
    print_error "Backup partition (LABEL=writable_backup) not found"
    print_error "This system may not have been created with the dual-partition setup"
    exit 1
fi

# Check if reset is already scheduled
if [[ -f "$RESET_FLAG_FILE" ]]; then
    print_warning "A system reset is already scheduled for next boot!"
    print_status "Use: sudo pi-reset.sh --cancel    to cancel the reset"
    print_status "Use: sudo pi-reset.sh --status    to check status"
    exit 1
fi

print_warning "⚠️  SYSTEM RESET SCHEDULED ⚠️"
print_warning ""
print_warning "This will reset the system to its original state on next boot!"
print_warning "ALL changes made to the system will be lost!"
print_warning ""
print_warning "The reset will happen automatically during boot, before"
print_warning "normal services start, avoiding filesystem conflicts."
print_warning ""
print_warning "What will happen:"
print_warning "  1. System will reboot"
print_warning "  2. Reset service will start early in boot process"
print_warning "  3. Active partition will be restored from backup"
print_warning "  4. System will continue normal boot with original state"
print_warning ""
read -p "Are you sure you want to schedule the reset? (yes/NO): " -r

if [[ "$REPLY" != "yes" ]]; then
    print_status "Reset cancelled"
    exit 0
fi

print_status "Setting up reset-on-boot system..."

# Create the boot-time reset script
cat > "$RESET_SCRIPT_PATH" << 'RESET_EOF'
#!/bin/bash
# Pi Reset Boot Script - Executed during boot to perform reset

set -e

# Logging functions
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a /var/log/pi-reset.log; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a /var/log/pi-reset.log; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" | tee -a /var/log/pi-reset.log; }

# Configuration
RESET_FLAG_FILE="/tmp/.pi-reset-scheduled"
BACKUP_LABEL="writable_backup"
ACTIVE_LABEL="writable"

log_info "Pi Reset Boot Service Started"

# Check if reset is actually scheduled
if [[ ! -f "$RESET_FLAG_FILE" ]]; then
    log_info "No reset flag found - exiting"
    exit 0
fi

log_info "Reset flag found - beginning system reset"

# Create mount points
TEMP_DIR=$(mktemp -d)
BACKUP_MOUNT="$TEMP_DIR/backup"
ACTIVE_MOUNT="$TEMP_DIR/active"

cleanup_on_exit() {
    log_info "Cleaning up mounts..."
    umount "$BACKUP_MOUNT" 2>/dev/null || true
    umount "$ACTIVE_MOUNT" 2>/dev/null || true
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup_on_exit EXIT INT TERM

mkdir -p "$BACKUP_MOUNT" "$ACTIVE_MOUNT"

# Find the actual device names for the partitions
BACKUP_DEVICE=$(blkid -L "$BACKUP_LABEL")
ACTIVE_DEVICE=$(blkid -L "$ACTIVE_LABEL")

if [[ -z "$BACKUP_DEVICE" ]] || [[ -z "$ACTIVE_DEVICE" ]]; then
    log_error "Could not find backup or active partitions"
    log_error "Backup device: $BACKUP_DEVICE"
    log_error "Active device: $ACTIVE_DEVICE"
    exit 1
fi

log_info "Found partitions - Backup: $BACKUP_DEVICE, Active: $ACTIVE_DEVICE"

# Mount backup partition
log_info "Mounting backup partition..."
if ! mount "$BACKUP_DEVICE" "$BACKUP_MOUNT"; then
    log_error "Failed to mount backup partition: $BACKUP_DEVICE"
    exit 1
fi

# Verify backup has content
if [[ ! -d "$BACKUP_MOUNT/etc" ]] || [[ ! -d "$BACKUP_MOUNT/usr" ]]; then
    log_error "Backup partition missing critical directories"
    exit 1
fi

# Mount active partition
log_info "Mounting active partition..."
if ! mount "$ACTIVE_DEVICE" "$ACTIVE_MOUNT"; then
    log_error "Failed to mount active partition: $ACTIVE_DEVICE"
    exit 1
fi

# Perform the reset using rsync
log_info "Restoring system from backup (this may take several minutes)..."
if rsync -axHAWXS --numeric-ids --delete \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/run \
    --exclude=/tmp \
    --exclude=/var/log/pi-reset.log \
    "$BACKUP_MOUNT/" "$ACTIVE_MOUNT/"; then
    
    log_success "System restored from backup successfully"
    
    # Restore reset scripts
    if [[ -f "$BACKUP_MOUNT/usr/local/bin/pi-reset.sh" ]]; then
        cp "$BACKUP_MOUNT/usr/local/bin/pi-reset.sh" "$ACTIVE_MOUNT/usr/local/bin/" 2>/dev/null || true
        chmod +x "$ACTIVE_MOUNT/usr/local/bin/pi-reset.sh" 2>/dev/null || true
        ln -sf /usr/local/bin/pi-reset.sh "$ACTIVE_MOUNT/usr/local/bin/reset-pi" 2>/dev/null || true
    fi
    
    # Remove reset flag and service
    rm -f "$RESET_FLAG_FILE"
    systemctl disable pi-reset-boot.service 2>/dev/null || true
    
    log_success "Reset completed successfully"
    log_info "System will continue normal boot with restored state"
    
else
    log_error "Failed to restore system from backup"
    log_error "System may be in inconsistent state"
    exit 1
fi

RESET_EOF

chmod +x "$RESET_SCRIPT_PATH"

# Create systemd service
cat > "$SYSTEMD_SERVICE_PATH" << 'SERVICE_EOF'
[Unit]
Description=Pi Reset Boot Service
Documentation=man:pi-reset(1)
DefaultDependencies=no
Conflicts=shutdown.target
After=systemd-remount-fs.service
Before=systemd-sysusers.service systemd-tmpfiles-setup.service
ConditionPathExists=/tmp/.pi-reset-scheduled

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pi-reset-boot.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutSec=0

[Install]
WantedBy=sysinit.target
SERVICE_EOF

# Enable the service
systemctl daemon-reload
systemctl enable pi-reset-boot.service

# Create reset flag
touch "$RESET_FLAG_FILE"

print_success "Reset scheduled successfully!"
print_status ""
print_status "What happens next:"
print_status "  1. Reset flag created: $RESET_FLAG_FILE"
print_status "  2. Boot service installed and enabled"
print_status "  3. On next reboot, reset will happen automatically"
print_status "  4. System will restore from backup and continue booting"
print_status ""
print_status "Management commands:"
print_status "  sudo pi-reset.sh --status    # Check if reset is scheduled"
print_status "  sudo pi-reset.sh --cancel    # Cancel scheduled reset"
print_status ""
print_warning "The system is now scheduled for reset on next boot!"

# Ask if user wants to reboot now
echo
read -p "Do you want to reboot now to perform the reset? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Rebooting system to perform reset..."
    systemctl reboot
else
    print_status "Reset scheduled - reboot manually when ready"
    print_status "The reset will happen automatically on next boot"
fi

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