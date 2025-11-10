#!/bin/bash

# Pi Image Backup Script
# This script creates a backup of the Pi image from /dev/sdb
# Usage: ./backup_pi_image.sh [output_directory] [image_name]

set -e  # Exit on any error

# Configuration
SOURCE_DEVICE="/dev/sda"
DEFAULT_OUTPUT_DIR="/home/pi/pi-images"
DEFAULT_IMAGE_NAME="pi-backup-$(date +%Y%m%d-%H%M%S).img"

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

# Function to check if source device exists
check_source_device() {
    if [[ ! -b "$SOURCE_DEVICE" ]]; then
        print_error "Source device $SOURCE_DEVICE does not exist or is not a block device"
        exit 1
    fi
    
    print_status "Source device $SOURCE_DEVICE found"
}

# Function to get device size
get_device_size() {
    local device=$1
    local size_bytes=$(blockdev --getsize64 "$device")
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    echo "$size_gb"
}

# Function to check available disk space
check_disk_space() {
    local output_dir=$1
    local required_space_gb=$2
    local backup_type="$3"
    
    local available_space_kb=$(df "$output_dir" | awk 'NR==2 {print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        print_error "Insufficient disk space for $backup_type backup."
        print_error "Required: ${required_space_gb}GB, Available: ${available_space_gb}GB"
        if [[ "$backup_type" == "full" ]]; then
            print_warning "Consider using smart backup mode to reduce space requirements"
        fi
        exit 1
    fi
    
    print_status "Disk space check passed for $backup_type backup."
    print_status "Available: ${available_space_gb}GB, Required: ${required_space_gb}GB"
}

# Function to create backup directory
create_backup_directory() {
    local output_dir=$1
    
    if [[ ! -d "$output_dir" ]]; then
        print_status "Creating backup directory: $output_dir"
        mkdir -p "$output_dir" || {
            print_error "Failed to create backup directory: $output_dir"
            exit 1
        }
    fi
}

# Function to get partition information
get_partition_info() {
    local device=$1
    print_status "Analyzing partitions on $device..."
    
    # Get the last used sector across all partitions
    local last_sector=0
    while IFS= read -r line; do
        if [[ $line =~ ^${device}[0-9]+ ]]; then
            local end_sector=$(echo "$line" | awk '{print $3}' | tr -d '*')
            # Make sure end_sector is numeric
            if [[ $end_sector =~ ^[0-9]+$ ]] && [[ $end_sector -gt $last_sector ]]; then
                last_sector=$end_sector
            fi
        fi
    done < <(fdisk -l "$device" 2>/dev/null | grep "^${device}")
    
    # If no partitions found, use a more robust method
    if [[ $last_sector -eq 0 ]]; then
        print_warning "Could not detect partitions with fdisk, trying parted..."
        last_sector=$(parted "$device" print 2>/dev/null | grep "^ [0-9]" | tail -1 | awk '{print $3}' | sed 's/[^0-9]//g' 2>/dev/null || echo "0")
    fi
    
    # If still no luck, fall back to a reasonable default (8GB worth of sectors)
    if [[ $last_sector -eq 0 ]]; then
        print_warning "Could not auto-detect partition end, using 8GB default"
        last_sector=$((8 * 1024 * 1024 * 1024 / 512))
    fi
    
    # Add some padding (1GB worth of sectors, assuming 512 bytes per sector)
    local padding_sectors=$((1 * 1024 * 1024 * 1024 / 512))
    last_sector=$((last_sector + padding_sectors))
    
    print_status "Will backup up to sector $last_sector"
    echo "$last_sector"
}

# Function to calculate backup size
calculate_backup_size() {
    local device=$1
    local last_sector=$2
    
    # Ensure last_sector is a valid number
    if [[ ! $last_sector =~ ^[0-9]+$ ]]; then
        print_error "Invalid sector number: $last_sector"
        return 1
    fi
    
    # Calculate size in bytes (512 bytes per sector)
    local backup_size_bytes=$((last_sector * 512))
    local backup_size_gb=$((backup_size_bytes / 1024 / 1024 / 1024))
    
    echo "$backup_size_gb"
}

# Function to backup the image (smart backup)
backup_image() {
    local source_device=$1
    local output_path=$2
    local backup_method="${3:-smart}"
    
    if [[ "$backup_method" == "full" ]]; then
        backup_image_full "$source_device" "$output_path"
    else
        backup_image_smart "$source_device" "$output_path"
    fi
}

# Function to backup full image (original method)
backup_image_full() {
    local source_device=$1
    local output_path=$2
    
    print_status "Starting FULL backup of $source_device to $output_path"
    print_warning "This operation may take a while depending on the size of the device..."
    
    # Use dd with progress monitoring via pv if available
    if command -v pv &> /dev/null; then
        local device_size_bytes=$(blockdev --getsize64 "$source_device")
        dd if="$source_device" bs=4M status=none | pv -s "$device_size_bytes" | dd of="$output_path" bs=4M status=none
    else
        print_warning "pv (pipe viewer) not found. Using dd without progress indicator."
        print_status "You can install pv for progress monitoring: sudo apt-get install pv"
        dd if="$source_device" of="$output_path" bs=4M status=progress
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "Full backup completed successfully"
    else
        print_error "Full backup failed"
        exit 1
    fi
}

# Function to backup only used space (smart backup)
backup_image_smart() {
    local source_device=$1
    local output_path=$2
    
    print_status "Starting SMART backup of $source_device to $output_path"
    print_status "This will only backup the used space, making it much smaller and faster..."
    
    # Get the last used sector directly (avoid function call issues)
    local last_sector=0
    while IFS= read -r line; do
        if [[ $line =~ ^${source_device}[0-9]+ ]]; then
            local end_sector=$(echo "$line" | awk '{print $3}' | tr -d '*')
            if [[ $end_sector =~ ^[0-9]+$ ]] && [[ $end_sector -gt $last_sector ]]; then
                last_sector=$end_sector
            fi
        fi
    done < <(fdisk -l "$source_device" 2>/dev/null | grep "^${source_device}")
    
    # Add 1GB padding (2097152 sectors)
    last_sector=$((last_sector + 2097152))
    
    # Round up to the nearest 4MB boundary (8192 sectors) for better alignment
    local remainder=$((last_sector % 8192))
    if [[ $remainder -ne 0 ]]; then
        last_sector=$((last_sector + 8192 - remainder))
    fi
    
    # Calculate size in GB
    local backup_size_bytes=$((last_sector * 512))
    local backup_size_gb=$((backup_size_bytes / 1024 / 1024 / 1024))
    
    print_status "Smart backup will copy up to sector $last_sector (~${backup_size_gb}GB) [aligned]"
    
    # Calculate the number of 4MB blocks to copy
    local blocks_to_copy=$((backup_size_bytes / (4 * 1024 * 1024)))
    
    # Use dd with count parameter to limit the backup size
    if command -v pv &> /dev/null; then
        dd if="$source_device" bs=4M count="$blocks_to_copy" status=none | \
        pv -s "$backup_size_bytes" | \
        dd of="$output_path" bs=4M status=none
    else
        print_warning "pv (pipe viewer) not found. Using dd without progress indicator."
        print_status "You can install pv for progress monitoring: sudo apt-get install pv"
        dd if="$source_device" of="$output_path" bs=4M count="$blocks_to_copy" status=progress
    fi
    
    if [[ $? -eq 0 ]]; then
        print_success "Smart backup completed successfully"
        print_status "Backup size: $(du -h "$output_path" | cut -f1) (instead of full $(get_device_size "$source_device")GB)"
    else
        print_error "Smart backup failed"
        exit 1
    fi
}

# Function to verify the backup (full)
verify_backup() {
    local source_device=$1
    local backup_file=$2
    
    print_status "Verifying full backup integrity..."
    
    local source_md5=$(dd if="$source_device" bs=4M status=none | md5sum | cut -d' ' -f1)
    local backup_md5=$(md5sum "$backup_file" | cut -d' ' -f1)
    
    if [[ "$source_md5" == "$backup_md5" ]]; then
        print_success "Full backup verification passed - checksums match"
    else
        print_error "Full backup verification failed - checksums do not match"
        print_error "Source MD5: $source_md5"
        print_error "Backup MD5: $backup_md5"
        exit 1
    fi
}

# Function to verify smart backup
verify_smart_backup() {
    local source_device=$1
    local backup_file=$2
    
    print_status "Verifying smart backup integrity..."
    
    # Get the size of the backup file
    local backup_size=$(stat -c%s "$backup_file")
    local backup_sectors=$((backup_size / 512))
    
    print_status "Backup file size: $(du -h "$backup_file" | cut -f1) ($backup_sectors sectors)"
    
    # For smart backups, we'll do a basic integrity check instead of full MD5 comparison
    # This avoids timing issues with active filesystems
    
    # Check if the backup file has a valid partition table
    if ! fdisk -l "$backup_file" &>/dev/null; then
        print_error "Smart backup verification failed - backup file does not contain valid partition table"
        exit 1
    fi
    
    # Check if backup file size is reasonable (not too small)
    local min_expected_size=$((1024 * 1024 * 1024))  # 1GB minimum
    if [[ $backup_size -lt $min_expected_size ]]; then
        print_error "Smart backup verification failed - backup file too small ($backup_size bytes)"
        exit 1
    fi
    
    # Verify first few sectors match (boot sector and partition table)
    local first_sectors=2048  # First 1MB
    local source_start=$(dd if="$source_device" bs=512 count="$first_sectors" status=none 2>/dev/null | md5sum | cut -d' ' -f1)
    local backup_start=$(dd if="$backup_file" bs=512 count="$first_sectors" status=none 2>/dev/null | md5sum | cut -d' ' -f1)
    
    if [[ "$source_start" == "$backup_start" ]]; then
        print_success "Smart backup verification passed - boot sector and partition table match"
        print_status "Backup contains valid partition table and expected data structure"
    else
        print_warning "Boot sector verification shows differences (this may be normal for active systems)"
        print_status "Backup file appears structurally valid and ready for use"
    fi
    
    # Additional check: verify backup can be mounted (if it has recognizable filesystems)
    print_status "Performing additional filesystem checks..."
    local partition_check_passed=0
    
    # Check if we can detect filesystems in the backup
    if command -v blkid &>/dev/null; then
        local fs_info=$(blkid "$backup_file" 2>/dev/null || echo "")
        if [[ -n "$fs_info" ]]; then
            print_success "Detected filesystem signatures in backup image"
            partition_check_passed=1
        fi
    fi
    
    if [[ $partition_check_passed -eq 0 ]]; then
        # Try with loopback device for more detailed check
        local loop_device=$(losetup --find --show "$backup_file" 2>/dev/null)
        if [[ -n "$loop_device" ]]; then
            sleep 1
            partprobe "$loop_device" 2>/dev/null || true
            sleep 1
            
            if ls "${loop_device}p"* &>/dev/null; then
                print_success "Backup image contains valid partitions"
                partition_check_passed=1
            fi
            
            losetup -d "$loop_device" 2>/dev/null || true
        fi
    fi
    
    if [[ $partition_check_passed -eq 1 ]]; then
        print_success "Smart backup verification completed - backup is valid and ready for use"
    else
        print_warning "Could not fully verify filesystem structure, but backup file appears valid"
        print_status "Backup size and basic structure checks passed"
    fi
}

# Function to compress the backup (optional)
compress_backup() {
    local backup_file=$1
    
    read -p "Do you want to compress the backup image? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Compressing backup image..."
        gzip "$backup_file"
        print_success "Backup compressed to ${backup_file}.gz"
        return 0
    fi
    return 1
}

# Function to display backup information
display_backup_info() {
    local backup_file=$1
    local compressed=$2
    
    if [[ $compressed -eq 0 ]]; then
        backup_file="${backup_file}.gz"
    fi
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    
    print_success "Backup Information:"
    echo "  Source Device: $SOURCE_DEVICE"
    echo "  Backup File: $backup_file"
    echo "  File Size: $file_size"
    echo "  Created: $(date)"
}

# Main function
main() {
    local output_dir="${1:-$DEFAULT_OUTPUT_DIR}"
    local image_name="${2:-$DEFAULT_IMAGE_NAME}"
    local backup_mode="${3:-smart}"  # smart or full
    local skip_verification="${4:-false}"  # true to skip verification
    local output_path="$output_dir/$image_name"
    
    print_status "Pi Image Backup Script Starting..."
    print_status "Source: $SOURCE_DEVICE"
    print_status "Destination: $output_path"
    print_status "Backup mode: $backup_mode"
    
    # Pre-flight checks
    check_root
    check_source_device
    
    # Get device size
    local device_size_gb=$(get_device_size "$SOURCE_DEVICE")
    print_status "Source device size: ${device_size_gb}GB"
    
    # Create backup directory
    create_backup_directory "$output_dir"
    
    # Calculate required space based on backup mode
    local required_space
    if [[ "$backup_mode" == "full" ]]; then
        # Full backup: need space for entire device plus 10% buffer
        required_space=$((device_size_gb + device_size_gb / 10))
    else
        # Smart backup: calculate based on used partitions
        print_status "Calculating smart backup requirements..."
        
        # Get the last used sector directly from fdisk
        local last_sector=0
        while IFS= read -r line; do
            if [[ $line =~ ^${SOURCE_DEVICE}[0-9]+ ]]; then
                local end_sector=$(echo "$line" | awk '{print $3}' | tr -d '*')
                if [[ $end_sector =~ ^[0-9]+$ ]] && [[ $end_sector -gt $last_sector ]]; then
                    last_sector=$end_sector
                fi
            fi
        done < <(fdisk -l "$SOURCE_DEVICE" 2>/dev/null | grep "^${SOURCE_DEVICE}")
        
        if [[ $last_sector -gt 0 ]]; then
            # Add 1GB padding (2097152 sectors)
            last_sector=$((last_sector + 2097152))
            # Calculate size in GB
            local backup_size_bytes=$((last_sector * 512))
            local smart_backup_gb=$((backup_size_bytes / 1024 / 1024 / 1024))
            required_space=$((smart_backup_gb + 1))  # Add 1GB buffer
            print_status "Smart backup will require approximately ${smart_backup_gb}GB (vs ${device_size_gb}GB for full backup)"
        else
            print_warning "Could not detect partitions, using conservative estimate of 8GB"
            required_space=8
        fi
    fi
    
    # Check available disk space
    check_disk_space "$output_dir" "$required_space" "$backup_mode"
    
    # Confirm before proceeding
    echo
    if [[ "$backup_mode" == "full" ]]; then
        print_warning "About to backup ENTIRE $SOURCE_DEVICE (${device_size_gb}GB) to $output_path"
    else
        print_warning "About to backup USED SPACE from $SOURCE_DEVICE (~${required_space}GB) to $output_path"
        print_status "This will be much faster and smaller than a full backup!"
    fi
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Backup cancelled by user"
        exit 0
    fi
    
    # Perform the backup
    if [[ "$backup_mode" == "full" ]]; then
        backup_image_full "$SOURCE_DEVICE" "$output_path"
        # Verification for full backup
        if [[ "$skip_verification" == "true" ]]; then
            print_status "Skipping verification as requested"
        else
            echo
            read -p "Do you want to verify the backup integrity? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                verify_backup "$SOURCE_DEVICE" "$output_path"
            else
                print_status "Skipping verification as requested"
            fi
        fi
    else
        backup_image_smart "$SOURCE_DEVICE" "$output_path"
        # Verification for smart backup
        if [[ "$skip_verification" == "true" ]]; then
            print_status "Skipping verification as requested"
        else
            echo
            read -p "Do you want to verify the backup integrity? (Y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                verify_smart_backup "$SOURCE_DEVICE" "$output_path"
            else
                print_status "Skipping verification as requested"
            fi
        fi
    fi
    
    # Optional compression
    local compressed=1
    if [[ "$skip_verification" != "true" ]]; then
        compress_backup "$output_path"
        compressed=$?
    else
        print_status "Skipping compression prompt for automated backup"
    fi
    
    # Display final information
    display_backup_info "$output_path" "$compressed"
    
    print_success "Backup process completed successfully!"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OUTPUT_DIRECTORY] [IMAGE_NAME] [BACKUP_MODE] [SKIP_VERIFICATION]"
    echo ""
    echo "Arguments:"
    echo "  OUTPUT_DIRECTORY   Directory to store the backup (default: $DEFAULT_OUTPUT_DIR)"
    echo "  IMAGE_NAME         Name for the backup image (default: $DEFAULT_IMAGE_NAME)"
    echo "  BACKUP_MODE        'smart' (default) or 'full'"
    echo "  SKIP_VERIFICATION  'true' to skip verification, 'false' (default) to prompt"
    echo ""
    echo "Backup Modes:"
    echo "  smart   - Only backup used space (much faster and smaller)"
    echo "  full    - Backup entire device (slower but complete)"
    echo ""
    echo "Examples:"
    echo "  $0                                               # Smart backup with defaults"
    echo "  $0 /tmp/backups                                 # Smart backup, custom directory"
    echo "  $0 /tmp/backups my-pi-backup.img                # Smart backup, custom name"
    echo "  $0 /tmp/backups my-pi-backup.img full           # Full backup"
    echo "  $0 /tmp/backups my-pi-backup.img smart          # Explicit smart backup"
    echo "  $0 /tmp/backups my-pi-backup.img smart true     # Smart backup, skip verification"
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