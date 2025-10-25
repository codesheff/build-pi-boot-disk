#!/bin/bash

# Raspberry Pi Boot Disk Creator with Recovery
# Creates a boot disk with main system and recovery partition

set -e

# Configuration
SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(realpath "$SCRIPT_DIR/..")"
IMAGES_DIR="$PROJECT_DIR/images"
CONFIGS_DIR="$PROJECT_DIR/configs"
RECOVERY_DIR="$PROJECT_DIR/recovery"
TEMP_DIR="/tmp/pi-boot-disk-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] TARGET_DEVICE

Creates a Raspberry Pi boot disk with recovery partition

ARGUMENTS:
    TARGET_DEVICE           Target device (e.g., /dev/sdb, /dev/mmcblk0)
                           WARNING: All data on this device will be erased!

OPTIONS:
    -i, --image IMAGE       Source Ubuntu image file (auto-detect if not specified)
    -s, --size SIZE         Recovery partition size in GB (default: 4)
    -n, --name NAME         System name for identification (default: pi-system)
    -y, --yes               Skip confirmation prompts
    -v, --verbose           Verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0 /dev/sdb                    # Create boot disk on /dev/sdb
    $0 -i custom.img /dev/mmcblk0  # Use specific image
    $0 -s 8 -n mypi /dev/sdb       # 8GB recovery, custom name

DISK LAYOUT:
    Partition 1: EFI System (256MB)        - Boot loader
    Partition 2: Main System (remaining)   - Primary Ubuntu installation  
    Partition 3: Recovery (4GB default)    - Recovery system and backup

EOF
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        log_info "Example: sudo $0 /dev/sdb"
        exit 1
    fi
}

# Function to validate target device
validate_device() {
    local device="$1"
    
    if [ ! -b "$device" ]; then
        log_error "Device $device does not exist or is not a block device"
        exit 1
    fi
    
    # Check if device is mounted
    if mount | grep -q "^$device"; then
        log_error "Device $device or its partitions are currently mounted"
        log_info "Please unmount all partitions first:"
        mount | grep "^$device" | while read line; do
            local part=$(echo "$line" | cut -d' ' -f1)
            echo "  sudo umount $part"
        done
        exit 1
    fi
    
    # Get device size
    local size_bytes=$(blockdev --getsize64 "$device")
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    log_info "Target device: $device"
    log_info "Device size: ${size_gb}GB"
    
    if [ $size_gb -lt 8 ]; then
        log_error "Device is too small (${size_gb}GB). Minimum 8GB required."
        exit 1
    fi
}

# Function to find Ubuntu image
find_image() {
    local specified_image="$1"
    
    if [ -n "$specified_image" ]; then
        if [ ! -f "$specified_image" ]; then
            log_error "Specified image file not found: $specified_image"
            exit 1
        fi
        echo "$specified_image"
        return
    fi
    
    # Auto-detect Ubuntu image
    local image_file=$(find "$IMAGES_DIR" -name "ubuntu-*.img" -type f | head -1)
    
    if [ -z "$image_file" ]; then
        log_error "No Ubuntu image found in $IMAGES_DIR"
        log_info "Please download an image first:"
        log_info "  ./scripts/download-image.sh"
        exit 1
    fi
    
    log_info "Auto-detected image: $(basename "$image_file")"
    echo "$image_file"
}

# Function to confirm destructive operation
confirm_operation() {
    local device="$1"
    local skip_confirm="$2"
    
    if [ "$skip_confirm" = "true" ]; then
        return
    fi
    
    log_warning "WARNING: This will completely erase all data on $device"
    log_warning "This operation cannot be undone!"
    echo
    read -p "Type 'YES' to continue: " confirmation
    
    if [ "$confirmation" != "YES" ]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

# Function to create partition table
create_partitions() {
    local device="$1"
    local recovery_size_gb="$2"
    
    log_info "Creating partition table on $device..."
    
    # Calculate sizes
    local device_size_bytes=$(blockdev --getsize64 "$device")
    local device_size_gb=$((device_size_bytes / 1024 / 1024 / 1024))
    local efi_size_mb=256
    local recovery_size_mb=$((recovery_size_gb * 1024))
    local main_size_gb=$((device_size_gb - recovery_size_gb - 1)) # -1 for EFI partition
    
    log_info "Partition layout:"
    log_info "  EFI System: ${efi_size_mb}MB"
    log_info "  Main System: ${main_size_gb}GB"
    log_info "  Recovery: ${recovery_size_gb}GB"
    
    # Unmount any existing partitions
    umount ${device}* 2>/dev/null || true
    
    # Create GPT partition table
    parted -s "$device" mklabel gpt
    
    # Create EFI system partition (256MB)
    parted -s "$device" mkpart primary fat32 1MiB ${efi_size_mb}MiB
    parted -s "$device" set 1 esp on
    
    # Create main system partition
    local main_start_mb=$((efi_size_mb + 1))
    local main_end_mb=$((device_size_gb * 1024 - recovery_size_mb))
    parted -s "$device" mkpart primary ext4 ${main_start_mb}MiB ${main_end_mb}MiB
    
    # Create recovery partition
    parted -s "$device" mkpart primary ext4 ${main_end_mb}MiB 100%
    
    # Inform kernel of partition changes
    partprobe "$device"
    sleep 2
    
    log_success "Partition table created successfully"
}

# Function to format partitions
format_partitions() {
    local device="$1"
    local system_name="$2"
    
    log_info "Formatting partitions..."
    
    # Determine partition naming scheme
    if [[ "$device" == *"mmcblk"* ]] || [[ "$device" == *"nvme"* ]]; then
        local efi_part="${device}p1"
        local main_part="${device}p2"
        local recovery_part="${device}p3"
    else
        local efi_part="${device}1"
        local main_part="${device}2"
        local recovery_part="${device}3"
    fi
    
    # Wait for partition devices to appear
    local count=0
    while [ ! -b "$efi_part" ] && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if [ ! -b "$efi_part" ]; then
        log_error "Partition devices not found. Check if $device supports partitioning."
        exit 1
    fi
    
    # Format EFI partition
    log_info "Formatting EFI partition ($efi_part)..."
    mkfs.fat -F32 -n "EFI" "$efi_part"
    
    # Format main partition
    log_info "Formatting main partition ($main_part)..."
    mkfs.ext4 -F -L "${system_name}-main" "$main_part"
    
    # Format recovery partition
    log_info "Formatting recovery partition ($recovery_part)..."
    mkfs.ext4 -F -L "${system_name}-recovery" "$recovery_part"
    
    log_success "All partitions formatted successfully"
    
    # Store partition info for later use
    echo "EFI_PART=$efi_part" > "$TEMP_DIR/partitions.conf"
    echo "MAIN_PART=$main_part" >> "$TEMP_DIR/partitions.conf"
    echo "RECOVERY_PART=$recovery_part" >> "$TEMP_DIR/partitions.conf"
}

# Function to write Ubuntu image to main partition
write_main_system() {
    local image_file="$1"
    local device="$2"
    
    source "$TEMP_DIR/partitions.conf"
    
    log_info "Writing Ubuntu image to main partition..."
    log_info "Source: $(basename "$image_file")"
    log_info "Target: $MAIN_PART"
    
    # Create mount points
    mkdir -p "$TEMP_DIR/image_mount"
    mkdir -p "$TEMP_DIR/main_mount"
    
    # Mount the Ubuntu image
    local loop_device=$(losetup -f --show "$image_file")
    partprobe "$loop_device"
    
    # Find the root partition in the image (usually p2)
    local image_root="${loop_device}p2"
    local image_boot="${loop_device}p1"
    
    if [ ! -b "$image_root" ]; then
        log_error "Could not find root partition in image"
        losetup -d "$loop_device"
        exit 1
    fi
    
    # Mount image partitions
    mount "$image_root" "$TEMP_DIR/image_mount"
    
    # Mount target main partition
    mount "$MAIN_PART" "$TEMP_DIR/main_mount"
    
    # Copy root filesystem
    log_info "Copying root filesystem (this may take several minutes)..."
    rsync -aHAXS --numeric-ids "$TEMP_DIR/image_mount/" "$TEMP_DIR/main_mount/"
    
    # Handle boot partition
    if [ -b "$image_boot" ]; then
        mkdir -p "$TEMP_DIR/boot_mount"
        mount "$image_boot" "$TEMP_DIR/boot_mount"
        
        # Copy boot files to main partition's /boot
        mkdir -p "$TEMP_DIR/main_mount/boot"
        rsync -aHAXS --numeric-ids "$TEMP_DIR/boot_mount/" "$TEMP_DIR/main_mount/boot/"
        
        umount "$TEMP_DIR/boot_mount"
    fi
    
    # Cleanup mounts
    umount "$TEMP_DIR/image_mount"
    umount "$TEMP_DIR/main_mount"
    losetup -d "$loop_device"
    
    log_success "Main system written successfully"
}

# Function to setup recovery system
setup_recovery_system() {
    local device="$1"
    local system_name="$2"
    
    source "$TEMP_DIR/partitions.conf"
    
    log_info "Setting up recovery system..."
    
    mkdir -p "$TEMP_DIR/recovery_mount"
    mount "$RECOVERY_PART" "$TEMP_DIR/recovery_mount"
    
    # Create recovery directory structure
    mkdir -p "$TEMP_DIR/recovery_mount/scripts"
    mkdir -p "$TEMP_DIR/recovery_mount/backup"
    mkdir -p "$TEMP_DIR/recovery_mount/logs"
    
    # Copy recovery scripts
    cp -r "$RECOVERY_DIR"/* "$TEMP_DIR/recovery_mount/scripts/"
    
    # Make scripts executable
    chmod +x "$TEMP_DIR/recovery_mount/scripts"/*.sh
    
    # Create recovery configuration
    cat > "$TEMP_DIR/recovery_mount/recovery.conf" << EOF
# Recovery System Configuration
SYSTEM_NAME="$system_name"
DEVICE="$device"
MAIN_PARTITION="$MAIN_PART"
RECOVERY_PARTITION="$RECOVERY_PART"
EFI_PARTITION="$EFI_PART"
CREATED_DATE="$(date)"
BACKUP_DATE=""
EOF
    
    umount "$TEMP_DIR/recovery_mount"
    
    log_success "Recovery system setup complete"
}

# Function to setup boot loader
setup_bootloader() {
    local device="$1"
    local system_name="$2"
    
    source "$TEMP_DIR/partitions.conf"
    
    log_info "Setting up boot loader..."
    
    # Mount partitions
    mkdir -p "$TEMP_DIR/efi_mount"
    mkdir -p "$TEMP_DIR/main_mount"
    
    mount "$EFI_PART" "$TEMP_DIR/efi_mount"
    mount "$MAIN_PART" "$TEMP_DIR/main_mount"
    
    # Copy boot files from main system to EFI partition
    if [ -d "$TEMP_DIR/main_mount/boot/firmware" ]; then
        # Raspberry Pi specific boot files
        cp -r "$TEMP_DIR/main_mount/boot/firmware"/* "$TEMP_DIR/efi_mount/"
    elif [ -d "$TEMP_DIR/main_mount/boot" ]; then
        # Standard boot files
        cp -r "$TEMP_DIR/main_mount/boot"/* "$TEMP_DIR/efi_mount/"
    fi
    
    # Create boot menu configuration
    cat > "$TEMP_DIR/efi_mount/config.txt" << 'EOF'
# Raspberry Pi Boot Configuration
# Enable recovery mode selection

# Basic settings
arm_64bit=1
enable_uart=1
gpu_mem=64

# Boot selection via GPIO (optional)
# gpio_in_pin=3
# gpio_in_pull=up

# Include original config if it exists
include config_original.txt
EOF
    
    # Backup original config if it exists
    if [ -f "$TEMP_DIR/efi_mount/config_original.txt" ]; then
        cp "$TEMP_DIR/efi_mount/config_original.txt" "$TEMP_DIR/efi_mount/config_backup.txt"
    fi
    
    # Setup boot script for recovery selection
    cat > "$TEMP_DIR/efi_mount/boot_menu.sh" << 'EOF'
#!/bin/bash
# Boot menu for recovery selection
# This script runs early in the boot process

RECOVERY_TRIGGER="/boot/recovery_mode"
MAIN_ROOT="PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p2)"
RECOVERY_ROOT="PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p3)"

if [ -f "$RECOVERY_TRIGGER" ]; then
    echo "root=$RECOVERY_ROOT" > /boot/cmdline.txt
    echo "Recovery mode activated"
else
    echo "root=$MAIN_ROOT" > /boot/cmdline.txt
    echo "Normal boot mode"
fi
EOF
    
    chmod +x "$TEMP_DIR/efi_mount/boot_menu.sh"
    
    # Update main system fstab for proper partition mounting
    cat >> "$TEMP_DIR/main_mount/etc/fstab" << EOF

# Recovery partition
$RECOVERY_PART /mnt/recovery ext4 defaults,noauto 0 2
EOF
    
    # Create recovery trigger script in main system
    cat > "$TEMP_DIR/main_mount/usr/local/bin/recovery-mode" << 'EOF'
#!/bin/bash
# Script to trigger recovery mode on next boot

RECOVERY_TRIGGER="/boot/recovery_mode"

case "$1" in
    enable)
        touch "$RECOVERY_TRIGGER"
        echo "Recovery mode will be activated on next reboot"
        echo "Reboot with: sudo reboot"
        ;;
    disable)
        rm -f "$RECOVERY_TRIGGER"
        echo "Recovery mode disabled"
        ;;
    status)
        if [ -f "$RECOVERY_TRIGGER" ]; then
            echo "Recovery mode: ENABLED (next boot)"
        else
            echo "Recovery mode: DISABLED"
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        echo "  enable  - Enable recovery mode on next boot"
        echo "  disable - Disable recovery mode"
        echo "  status  - Check recovery mode status"
        ;;
esac
EOF
    
    chmod +x "$TEMP_DIR/main_mount/usr/local/bin/recovery-mode"
    
    # Cleanup
    umount "$TEMP_DIR/efi_mount"
    umount "$TEMP_DIR/main_mount"
    
    log_success "Boot loader setup complete"
}

# Function to create initial backup
create_initial_backup() {
    local device="$1"
    
    source "$TEMP_DIR/partitions.conf"
    
    log_info "Creating initial backup of main system..."
    
    mkdir -p "$TEMP_DIR/main_mount"
    mkdir -p "$TEMP_DIR/recovery_mount"
    
    mount "$MAIN_PART" "$TEMP_DIR/main_mount"
    mount "$RECOVERY_PART" "$TEMP_DIR/recovery_mount"
    
    # Create compressed backup
    log_info "Creating system backup (this may take several minutes)..."
    tar -czf "$TEMP_DIR/recovery_mount/backup/system_backup.tar.gz" \
        -C "$TEMP_DIR/main_mount" \
        --exclude="proc/*" \
        --exclude="sys/*" \
        --exclude="dev/*" \
        --exclude="tmp/*" \
        --exclude="var/cache/*" \
        --exclude="var/log/*" \
        .
    
    # Update recovery configuration with backup date
    sed -i "s/BACKUP_DATE=\"\"/BACKUP_DATE=\"$(date)\"/" \
        "$TEMP_DIR/recovery_mount/recovery.conf"
    
    umount "$TEMP_DIR/main_mount"
    umount "$TEMP_DIR/recovery_mount"
    
    log_success "Initial backup created successfully"
}

# Main function
main() {
    local image_file=""
    local recovery_size=4
    local system_name="pi-system"
    local skip_confirm="false"
    local verbose="false"
    local target_device=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image)
                image_file="$2"
                shift 2
                ;;
            -s|--size)
                recovery_size="$2"
                shift 2
                ;;
            -n|--name)
                system_name="$2"
                shift 2
                ;;
            -y|--yes)
                skip_confirm="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                set -x
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$target_device" ]; then
                    target_device="$1"
                else
                    log_error "Multiple devices specified"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate arguments
    if [ -z "$target_device" ]; then
        log_error "Target device not specified"
        show_usage
        exit 1
    fi
    
    # Check requirements
    check_root
    validate_device "$target_device"
    
    # Find Ubuntu image
    image_file=$(find_image "$image_file")
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Confirm operation
    confirm_operation "$target_device" "$skip_confirm"
    
    log_info "Starting boot disk creation..."
    log_info "Image: $(basename "$image_file")"
    log_info "Target: $target_device"
    log_info "Recovery size: ${recovery_size}GB"
    log_info "System name: $system_name"
    
    # Create the boot disk
    create_partitions "$target_device" "$recovery_size"
    format_partitions "$target_device" "$system_name"
    write_main_system "$image_file" "$target_device"
    setup_recovery_system "$target_device" "$system_name"
    setup_bootloader "$target_device" "$system_name"
    create_initial_backup "$target_device"
    
    log_success "Boot disk creation completed successfully!"
    echo
    log_info "Boot disk is ready: $target_device"
    log_info "System name: $system_name"
    log_info "Recovery partition size: ${recovery_size}GB"
    echo
    log_info "Usage:"
    log_info "  - Boot normally: Just insert and boot"
    log_info "  - Enable recovery: sudo recovery-mode enable && sudo reboot"
    log_info "  - Check status: sudo recovery-mode status"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        # Unmount any remaining mounts
        umount "$TEMP_DIR"/* 2>/dev/null || true
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup on exit
trap cleanup EXIT

# Check dependencies
for cmd in parted mkfs.fat mkfs.ext4 rsync tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        log_error "Please install required packages:"
        log_error "  sudo apt update"
        log_error "  sudo apt install parted dosfstools e2fsprogs rsync tar"
        exit 1
    fi
done

# Run main function
main "$@"