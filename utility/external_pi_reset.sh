#!/bin/bash

# External Pi Reset Script
# This script can safely reset a Pi disk from an external system
# Restores active partition (3) from backup partition (2)
# Usage: ./external_pi_reset.sh [target_device]

set -e

# Configuration
DEFAULT_TARGET_DEVICE="/dev/sda"

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

# Function to validate target device
validate_target_device() {
    local target_device="$1"
    
    if [[ ! -b "$target_device" ]]; then
        print_error "Target device not found or not a block device: $target_device"
        exit 1
    fi
    
    # Check that it has the expected partitions
    if [[ ! -b "${target_device}2" ]] || [[ ! -b "${target_device}3" ]]; then
        print_error "Target device does not have expected partitions ${target_device}2 and ${target_device}3"
        exit 1
    fi
    
    # Verify partition labels
    local backup_label=$(blkid -s LABEL -o value "${target_device}2" 2>/dev/null || echo "")
    local active_label=$(blkid -s LABEL -o value "${target_device}3" 2>/dev/null || echo "")
    
    if [[ "$backup_label" != "writable_backup" ]] || [[ "$active_label" != "writable" ]]; then
        print_error "Target device partitions do not have expected labels:"
        print_error "  ${target_device}2 has label: '$backup_label' (expected: 'writable_backup')"
        print_error "  ${target_device}3 has label: '$active_label' (expected: 'writable')"
        exit 1
    fi
    
    print_success "Validated target device: $target_device"
}

# Function to perform the reset
perform_reset() {
    local target_device="$1"
    
    print_status "Starting external Pi reset for $target_device..."
    
    # Create temporary mount points
    local temp_dir=$(mktemp -d)
    local backup_mount="$temp_dir/backup"
    local active_mount="$temp_dir/active"
    
    # Set up cleanup trap
    cleanup_on_exit() {
        print_status "Cleaning up..."
        umount "$backup_mount" 2>/dev/null || true
        umount "$active_mount" 2>/dev/null || true
        rm -rf "$temp_dir" 2>/dev/null || true
    }
    trap cleanup_on_exit EXIT INT TERM
    
    mkdir -p "$backup_mount" "$active_mount"
    
    # Mount both partitions
    print_status "Mounting partitions..."
    mount "${target_device}2" "$backup_mount"
    mount "${target_device}3" "$active_mount"
    
    # Verify backup partition has expected content
    if [[ ! -d "$backup_mount/etc" ]] || [[ ! -d "$backup_mount/usr" ]] || [[ ! -d "$backup_mount/var" ]]; then
        print_error "Backup partition does not contain expected system directories"
        exit 1
    fi
    
    # Perform the reset using rsync
    print_status "Restoring system from backup (this may take several minutes)..."
    rsync -axHAWXS --numeric-ids --delete \
        --exclude=/proc \
        --exclude=/sys \
        --exclude=/dev \
        --exclude=/run \
        --exclude=/tmp \
        "$backup_mount/" "$active_mount/"
    
    # Ensure reset script is present
    if [[ -f "$backup_mount/usr/local/bin/pi-reset.sh" ]]; then
        cp "$backup_mount/usr/local/bin/pi-reset.sh" "$active_mount/usr/local/bin/"
        chmod +x "$active_mount/usr/local/bin/pi-reset.sh"
        ln -sf /usr/local/bin/pi-reset.sh "$active_mount/usr/local/bin/reset-pi" 2>/dev/null || true
    fi
    
    # Verify critical files exist
    if [[ ! -f "$active_mount/etc/fstab" ]] || [[ ! -f "$active_mount/etc/passwd" ]]; then
        print_error "Critical system files missing after restore"
        exit 1
    fi
    
    sync  # Ensure all data is written to disk
    
    print_success "External Pi reset completed successfully!"
    print_status "The Pi disk at $target_device has been reset to its original state"
    print_status "Active partition (3) restored from backup partition (2)"
    print_status "It is now safe to move the disk to a Pi and boot normally"
}

# Main function
main() {
    local target_device="${1:-$DEFAULT_TARGET_DEVICE}"
    
    print_status "External Pi Reset Script Starting..."
    
    # Pre-flight checks
    check_root
    validate_target_device "$target_device"
    
    # Final confirmation
    echo
    print_warning "About to reset Pi disk at $target_device"
    print_warning "This will restore partition 3 (active) from partition 2 (backup)"
    print_warning "All changes on the active partition will be lost!"
    print_status "Target device: $target_device"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled by user"
        exit 0
    fi
    
    # Perform the reset
    perform_reset "$target_device"
}

# Show usage information
show_usage() {
    echo "External Pi Reset Script"
    echo "Usage: $0 [TARGET_DEVICE]"
    echo ""
    echo "This script safely resets a Pi disk from an external system."
    echo "It restores the active partition from the backup partition."
    echo ""
    echo "Arguments:"
    echo "  TARGET_DEVICE  Pi disk device to reset (default: $DEFAULT_TARGET_DEVICE)"
    echo ""
    echo "Examples:"
    echo "  $0              # Reset disk at $DEFAULT_TARGET_DEVICE"
    echo "  $0 /dev/sdb     # Reset disk at /dev/sdb"
    echo ""
    echo "Requirements:"
    echo "  - Must be run as root (use sudo)"
    echo "  - Target device must have dual-partition setup"
    echo "  - Target device should NOT be mounted or in use"
    echo ""
    echo "Note: This is safer than running pi-reset.sh from the Pi itself,"
    echo "      as it doesn't modify the running system."
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"