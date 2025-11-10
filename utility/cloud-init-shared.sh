#!/bin/bash
# Shared Cloud-Init Functions
# Common functions for cloud-init file management used by multiple scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions (only define if not already defined)
if ! command -v print_info >/dev/null 2>&1; then
    print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
    print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
    print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
fi

# Function to copy cloud-init files from reference directory to target
# Usage: copy_cloud_init_files TARGET_MOUNT_POINT [SOURCE_DIR] [DRY_RUN]
copy_cloud_init_files() {
    local mount_point="$1"
    local source_dir="${2:-$(dirname "${BASH_SOURCE[0]}")/../cloud-init-files}"
    local dry_run="${3:-false}"
    
    # Check if source directory exists
    if [[ ! -d "$source_dir" ]]; then
        print_error "Cloud-init files directory not found: $source_dir"
        return 1
    fi
    
    print_info "Copying cloud-init files from reference directory..."
    print_info "  Source: $source_dir"
    print_info "  Target: $mount_point"
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "DRY RUN: Would copy the following files:"
        for file in user-data meta-data network-config cmdline.txt; do
            if [[ -f "$source_dir/$file" ]]; then
                echo "  - $file (from reference directory)"
            fi
        done
        return 0
    fi
    
    # Copy cloud-init files from reference directory
    local files_copied=0
    for file in user-data meta-data network-config cmdline.txt; do
        if [[ -f "$source_dir/$file" ]]; then
            if [[ -w "$mount_point" ]]; then
                cp "$source_dir/$file" "$mount_point/" || { print_error "Failed to copy $file"; return 1; }
            else
                sudo cp "$source_dir/$file" "$mount_point/" || { print_error "Failed to copy $file"; return 1; }
            fi
            print_success "Copied $file"
            ((files_copied++))
        else
            print_warning "Reference file not found: $source_dir/$file"
        fi
    done
    
    if [[ $files_copied -eq 0 ]]; then
        print_warning "No cloud-init files were copied"
        return 1
    fi
    
    print_success "Successfully copied $files_copied cloud-init files"
    return 0
}

# Function to mount a partition temporarily if it's a block device
# Usage: mount_partition_if_needed DEVICE_OR_PATH
# Returns: mount_point was_already_mounted
mount_partition_if_needed() {
    local device="$1"
    local mount_point was_mounted="true"
    
    if [[ -b "$device" ]]; then
        # It's a block device - check if already mounted
        mount_point=$(mount | grep "^$device " | awk '{print $3}' | head -1 || true)
        if [[ -n "$mount_point" ]]; then
            echo "$mount_point false"  # mounted but we didn't mount it
            return 0
        fi
        
        # Create temporary mount point
        mount_point=$(mktemp -d)
        if ! sudo mount "$device" "$mount_point" 2>/dev/null; then
            print_error "Failed to mount $device"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
        was_mounted="false"
        echo "$mount_point true"  # we mounted it
    else
        # Assume it's already a mount point or directory
        if [[ -d "$device" ]]; then
            echo "$device false"  # directory, no unmounting needed
        else
            print_error "Path does not exist: $device"
            return 1
        fi
    fi
}

# Function to unmount a partition if we mounted it
# Usage: unmount_partition_if_needed DEVICE MOUNT_POINT WE_MOUNTED_IT
unmount_partition_if_needed() {
    local device="$1"
    local mount_point="$2"
    local we_mounted_it="$3"
    
    if [[ -b "$device" ]] && [[ "$we_mounted_it" == "true" ]]; then
        sudo umount "$mount_point" 2>/dev/null || true
        rmdir "$mount_point" 2>/dev/null || true
    fi
}

# High-level function to apply cloud-init files to a target
# Usage: apply_cloud_init_files TARGET_DEVICE_OR_PATH [SOURCE_DIR] [DRY_RUN]
apply_cloud_init_files() {
    local target="$1"
    local source_dir="${2:-$(dirname "${BASH_SOURCE[0]}")/../cloud-init-files}"
    local dry_run="${3:-false}"
    
    # Mount the target if needed
    local mount_result
    mount_result=$(mount_partition_if_needed "$target")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local mount_point we_mounted_it
    read mount_point we_mounted_it <<< "$mount_result"
    
    # Copy the files
    local result=0
    if ! copy_cloud_init_files "$mount_point" "$source_dir" "$dry_run"; then
        result=1
    fi
    
    # Cleanup
    unmount_partition_if_needed "$target" "$mount_point" "$we_mounted_it"
    
    return $result
}

# Function to show current cloud-init files on a partition
# Usage: show_current_cloud_init_files TARGET_DEVICE_OR_PATH
show_current_cloud_init_files() {
    local target="$1"
    
    # Mount the target if needed
    local mount_result
    mount_result=$(mount_partition_if_needed "$target")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local mount_point we_mounted_it
    read mount_point we_mounted_it <<< "$mount_result"
    
    print_info "Current cloud-init files on partition:"
    echo ""
    
    for file in user-data meta-data network-config cmdline.txt; do
        if [[ -f "$mount_point/$file" ]]; then
            local size=$(stat -c%s "$mount_point/$file" 2>/dev/null || echo "0")
            local modified=$(stat -c%y "$mount_point/$file" 2>/dev/null || echo "Unknown")
            echo "  ✓ $file - ${size} bytes - Modified: $modified"
        else
            echo "  ✗ $file - Missing"
        fi
    done
    echo ""
    
    # Cleanup
    unmount_partition_if_needed "$target" "$mount_point" "$we_mounted_it"
    
    return 0
}