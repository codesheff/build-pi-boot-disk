#!/bin/bash
# Recreate Cloud-Init Files on Existing Partition
# This script updates cloud-init files on an existing boot partition without recreating the entire disk

set -euo pipefail

# Source shared cloud-init functions
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$SCRIPT_DIR/cloud-init-shared.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default values
DEFAULT_TEMPLATES_DIR="$(dirname "$(realpath "$0")")/../cloud-init-files"

show_usage() {
    echo "Recreate Cloud-Init Files on Existing Partition"
    echo ""
    echo "Usage: $0 [OPTIONS] TARGET_PARTITION [HOSTNAME] [USERNAME]"
    echo ""
    echo "Arguments:"
    echo "  TARGET_PARTITION    Boot partition to update (e.g., /dev/sda1, /mnt/boot)"
    echo "  HOSTNAME           System hostname (optional, not used with file-copy approach)"
    echo "  USERNAME           User account name (optional, not used with file-copy approach)"
    echo ""
    echo "Options:"
    echo "  --templates-dir DIR    Path to cloud-init templates directory"
    echo "  --backup              Create backup of existing files before updating"
    echo "  --dry-run             Show what would be done without making changes"
    echo "  --force               Overwrite existing files without confirmation"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 /dev/sda1                        # Update boot partition with default settings"
    echo "  $0 /mnt/boot mypi pi                # Update mounted partition with custom settings"
    echo "  $0 --backup /dev/sda1               # Update with backup of existing files"
    echo "  $0 --dry-run /dev/sda1              # Preview changes without applying"
    echo ""
    echo "The script will:"
    echo "  1. Mount the partition if it's a block device"
    echo "  2. Generate new cloud-init files from templates"
    echo "  3. Optionally backup existing files"
    echo "  4. Update cloud-init files on the partition"
    echo "  5. Preserve other boot files (kernels, device trees, etc.)"
}

# Function to check if a path is a block device
is_block_device() {
    [[ -b "$1" ]]
}

# Function to get mount point for a device
get_mount_point() {
    local device="$1"
    if is_block_device "$device"; then
        mount | grep "^$device " | awk '{print $3}' | head -1
    else
        echo "$device"
    fi
}

# Function to mount partition temporarily
mount_partition() {
    local partition="$1"
    local mount_point
    
    if is_block_device "$partition"; then
        # Check if already mounted
        mount_point=$(get_mount_point "$partition")
        if [[ -n "$mount_point" ]]; then
            echo "$mount_point"
            return 0
        fi
        
        # Create temporary mount point
        mount_point=$(mktemp -d)
        if ! sudo mount "$partition" "$mount_point" 2>/dev/null; then
            print_error "Failed to mount $partition"
            rmdir "$mount_point"
            return 1
        fi
        echo "$mount_point"
    else
        # Assume it's already a mount point or directory
        if [[ -d "$partition" ]]; then
            echo "$partition"
        else
            print_error "Path does not exist: $partition"
            return 1
        fi
    fi
}

# Function to unmount partition if we mounted it
unmount_partition() {
    local partition="$1"
    local mount_point="$2"
    local was_mounted="$3"
    
    if is_block_device "$partition" && [[ "$was_mounted" == "false" ]]; then
        sudo umount "$mount_point" 2>/dev/null || true
        rmdir "$mount_point" 2>/dev/null || true
    fi
}

# Function to backup existing cloud-init files
backup_existing_files() {
    local mount_point="$1"
    local backup_dir="$mount_point/.cloud-init-backup-$(date +%Y%m%d-%H%M%S)"
    
    print_info "Creating backup of existing cloud-init files..."
    
    # Create backup directory (use sudo only if needed)
    if [[ -w "$mount_point" ]]; then
        mkdir -p "$backup_dir"
    else
        sudo mkdir -p "$backup_dir"
    fi
    
    # Backup cloud-init files if they exist
    local files_backed_up=0
    for file in user-data meta-data network-config cmdline.txt; do
        if [[ -f "$mount_point/$file" ]]; then
            if [[ -w "$mount_point" ]]; then
                cp "$mount_point/$file" "$backup_dir/"
            else
                sudo cp "$mount_point/$file" "$backup_dir/"
            fi
            print_info "Backed up: $file"
            files_backed_up=$((files_backed_up + 1))
        fi
    done
    
    if [[ $files_backed_up -eq 0 ]]; then
        if [[ -w "$mount_point" ]]; then
            rmdir "$backup_dir"
        else
            sudo rmdir "$backup_dir"
        fi
        print_warning "No existing cloud-init files found to backup"
    else
        print_success "Backed up $files_backed_up files to: $(basename "$backup_dir")"
    fi
}

# Function to generate cloud-init files (using shared function)
generate_cloud_init_files() {
    local mount_point="$1"
    local hostname="$2"
    local username="$3"
    local templates_dir="$4"
    local dry_run="$5"
    
    # Use the shared function to copy files
    copy_cloud_init_files "$mount_point" "$templates_dir" "$dry_run"
}

# Function to show current cloud-init files (using shared function)
show_current_files() {
    local mount_point="$1"
    show_current_cloud_init_files "$mount_point"
}

# Function to confirm operation
confirm_operation() {
    local partition="$1"
    local operation="$2"
    
    print_warning "About to $operation cloud-init files on: $partition"
    print_warning "This will overwrite existing cloud-init configuration files"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled by user"
        return 1
    fi
    return 0
}

# Main function
main() {
    local partition=""
    local hostname=""
    local username=""
    local templates_dir="$DEFAULT_TEMPLATES_DIR"
    local backup="false"
    local dry_run="false"
    local force="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --templates-dir)
                if [[ -z "${2:-}" ]]; then
                    print_error "--templates-dir requires a directory path"
                    exit 1
                fi
                templates_dir="$2"
                shift 2
                ;;
            --backup)
                backup="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$partition" ]]; then
                    partition="$1"
                elif [[ -z "$hostname" ]]; then
                    hostname="$1"
                elif [[ -z "$username" ]]; then
                    username="$1"
                else
                    print_error "Too many arguments"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$partition" ]]; then
        print_error "TARGET_PARTITION is required"
        show_usage
        exit 1
    fi
    
    # Validate templates directory
    if [[ ! -d "$templates_dir" ]]; then
        print_error "Templates directory not found: $templates_dir"
        exit 1
    fi
    
    # Validate partition
    if ! is_block_device "$partition" && ! [[ -d "$partition" ]]; then
        print_error "Invalid partition: $partition (must be a block device or directory)"
        exit 1
    fi
    
    print_info "Cloud-Init Files Recreation Starting..."
    print_info "Target partition: $partition"
    print_info "Cloud-init files directory: $templates_dir"
    print_info "Using direct file copy approach (hostname/username parameters ignored)"
    echo ""
    
    # Mount partition
    local mount_point was_mounted="true"
    
    mount_point=$(get_mount_point "$partition")
    if [[ -z "$mount_point" ]]; then
        mount_point=$(mount_partition "$partition")
        was_mounted="false"
    fi
    
    if [[ -z "$mount_point" ]]; then
        print_error "Failed to mount partition"
        exit 1
    fi
    
    print_info "Mounted at: $mount_point"
    
    # Show current files
    show_current_files "$mount_point"
    
    # Confirm operation unless forced or dry-run
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        if ! confirm_operation "$partition" "recreate"; then
            unmount_partition "$partition" "$mount_point" "$was_mounted"
            exit 0
        fi
    fi
    
    # Backup existing files if requested
    if [[ "$backup" == "true" && "$dry_run" != "true" ]]; then
        backup_existing_files "$mount_point"
    fi
    
    # Generate new cloud-init files
    generate_cloud_init_files "$mount_point" "$hostname" "$username" "$templates_dir" "$dry_run"
    
    if [[ "$dry_run" != "true" ]]; then
        echo ""
        print_success "Cloud-init files recreated successfully!"
        
        # Show updated files
        show_current_files "$mount_point"
    fi
    
    # Cleanup
    unmount_partition "$partition" "$mount_point" "$was_mounted"
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run completed - no changes made"
    else
        print_success "Recreation completed successfully!"
        print_info "The partition is ready to boot with updated cloud-init configuration"
    fi
}

# Check if running as root for some operations
if [[ $EUID -ne 0 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
    if [[ $# -gt 0 ]] && ! [[ -d "${!#}" ]]; then
        print_warning "This script may need sudo privileges for mounting block devices"
        print_info "If you encounter permission errors, try running with sudo"
    fi
fi

main "$@"