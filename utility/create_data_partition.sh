#!/bin/bash

# Create Data Partition Script
# This script creates a new data partition in the available free space
# Usage: ./create_data_partition.sh [device] [size]

set -e

# Configuration
DEFAULT_DEVICE="/dev/mmcblk0"
DEFAULT_SIZE="all"  # Use all available space

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to validate device
validate_device() {
    local device="$1"
    
    if [[ ! -b "$device" ]]; then
        print_error "Device not found or not a block device: $device"
        exit 1
    fi
    
    print_status "Validated device: $device"
}

# Function to show current partition layout
show_current_layout() {
    local device="$1"
    
    print_status "Current partition layout:"
    parted "$device" print free
    echo
}

# Function to find next available partition number
find_next_partition_number() {
    local device="$1"
    
    # Get the highest partition number currently in use
    local max_partition=$(parted "$device" print | grep "^ [0-9]" | awk '{print $1}' | sort -n | tail -1)
    local next_partition=$((max_partition + 1))
    
    # Check if we're hitting the primary partition limit (4 for MBR)
    if [[ $next_partition -gt 4 ]]; then
        print_error "Cannot create more than 4 primary partitions with MBR partition table"
        print_error "Consider converting to GPT or using extended partitions"
        exit 1
    fi
    
    echo "$next_partition"
}

# Function to get available free space
get_free_space() {
    local device="$1"
    
    # Get free space info - look for the largest free space block
    local free_space_info=$(parted "$device" print free | grep "Free Space" | tail -1)
    
    if [[ -z "$free_space_info" ]]; then
        print_error "No free space available on $device"
        exit 1
    fi
    
    # Extract start and end positions
    local free_start=$(echo "$free_space_info" | awk '{print $1}')
    local free_end=$(echo "$free_space_info" | awk '{print $2}')
    local free_size=$(echo "$free_space_info" | awk '{print $3}')
    
    print_status "Available free space: $free_size (from $free_start to $free_end)"
    
    # Export for use in other functions
    export FREE_START="$free_start"
    export FREE_END="$free_end"
    export FREE_SIZE="$free_size"
}

# Function to create the data partition
create_data_partition() {
    local device="$1"
    local size="$2"
    local partition_num="$3"
    
    print_status "Creating data partition..."
    
    if [[ "$size" == "all" ]]; then
        # Use all available free space
        print_status "Using all available free space ($FREE_SIZE)"
        parted "$device" mkpart primary ext4 "$FREE_START" "$FREE_END"
    else
        # Use specified size
        print_status "Creating partition with size: $size"
        parted "$device" mkpart primary ext4 "$FREE_START" "$size"
    fi
    
    # Get the actual partition device name
    if [[ "$device" =~ mmcblk|nvme|loop ]]; then
        local partition_device="${device}p${partition_num}"
    else
        local partition_device="${device}${partition_num}"
    fi
    
    # Wait for the partition to be recognized
    sleep 2
    partprobe "$device"
    sleep 2
    
    if [[ ! -b "$partition_device" ]]; then
        print_error "Partition $partition_device was not created successfully"
        exit 1
    fi
    
    print_success "Partition $partition_device created successfully"
    echo "$partition_device"
}

# Function to format the data partition
format_data_partition() {
    local partition_device="$1"
    
    print_status "Formatting data partition as ext4..."
    
    # Format with a descriptive label
    mkfs.ext4 -F -L "pi-data" "$partition_device"
    
    print_success "Data partition formatted successfully with label 'pi-data'"
}

# Function to create mount point and update fstab
setup_mount_point() {
    local partition_device="$1"
    local mount_point="/mnt/pi-data"
    
    print_status "Setting up mount point at $mount_point..."
    
    # Create mount point directory
    mkdir -p "$mount_point"
    
    # Get UUID of the partition
    local uuid=$(blkid -s UUID -o value "$partition_device")
    
    if [[ -z "$uuid" ]]; then
        print_error "Could not get UUID for $partition_device"
        exit 1
    fi
    
    # Check if entry already exists in fstab
    if grep -q "$uuid" /etc/fstab; then
        print_warning "Entry for this partition already exists in /etc/fstab"
    else
        # Add entry to fstab
        print_status "Adding entry to /etc/fstab..."
        echo "UUID=$uuid $mount_point ext4 defaults 0 2" >> /etc/fstab
        print_success "Added entry to /etc/fstab"
    fi
    
    # Mount the partition
    print_status "Mounting the new data partition..."
    mount "$mount_point"
    
    # Set permissions so pi user can write to it
    chown pi:pi "$mount_point"
    chmod 755 "$mount_point"
    
    print_success "Data partition mounted at $mount_point"
    print_status "Partition is owned by user 'pi' and ready for use"
}

# Function to show final information
show_final_info() {
    local device="$1"
    local partition_device="$2"
    
    print_success "Data partition creation completed successfully!"
    echo
    print_status "New partition layout:"
    parted "$device" print
    echo
    print_status "Filesystem information:"
    df -h "$partition_device"
    echo
    print_status "Usage:"
    echo "  - Data partition: $partition_device"
    echo "  - Mount point: /mnt/pi-data"
    echo "  - Label: pi-data"
    echo "  - Owner: pi user"
    echo "  - Auto-mounted at boot via /etc/fstab"
    echo
    print_status "You can now store data in /mnt/pi-data"
}

# Main function
main() {
    local device="${1:-$DEFAULT_DEVICE}"
    local size="${2:-$DEFAULT_SIZE}"
    
    print_status "Data Partition Creation Script Starting..."
    
    # Pre-flight checks
    check_root
    validate_device "$device"
    
    # Show current layout
    show_current_layout "$device"
    
    # Get free space information
    get_free_space "$device"
    
    # Find next partition number
    local next_partition=$(find_next_partition_number "$device")
    print_status "Will create partition $next_partition"
    
    # Confirmation
    echo
    print_warning "About to create a new data partition on $device"
    print_status "Partition number: $next_partition"
    print_status "Size: $([[ "$size" == "all" ]] && echo "All available space ($FREE_SIZE)" || echo "$size")"
    print_status "Filesystem: ext4"
    print_status "Label: pi-data"
    print_status "Mount point: /mnt/pi-data"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled by user"
        exit 0
    fi
    
    # Create and format the partition
    local partition_device=$(create_data_partition "$device" "$size" "$next_partition")
    format_data_partition "$partition_device"
    setup_mount_point "$partition_device"
    
    # Show final information
    show_final_info "$device" "$partition_device"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [DEVICE] [SIZE]"
    echo ""
    echo "Arguments:"
    echo "  DEVICE  Target device (default: $DEFAULT_DEVICE)"
    echo "  SIZE    Partition size or 'all' for all free space (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Use default device, all free space"
    echo "  $0 /dev/sda                 # Specify device, all free space"
    echo "  $0 /dev/mmcblk0 10GB        # Specify device and size"
    echo ""
    echo "The script will:"
    echo "  - Create a new ext4 partition with label 'pi-data'"
    echo "  - Mount it at /mnt/pi-data"
    echo "  - Add it to /etc/fstab for auto-mounting"
    echo "  - Set ownership to 'pi' user"
    echo ""
    echo "Note: This script must be run as root (use sudo)"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"