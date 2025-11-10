#!/bin/bash
# Cloud-Init Files Comparison Script

# Compare cloud-init files between two filesystems
# Can work with block devices, mount points, or directories

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}"; }
print_subheader() { echo -e "${MAGENTA}--- $1 ---${NC}"; }

# Cloud-init files to compare
CLOUD_INIT_FILES=("user-data" "meta-data" "network-config" "cmdline.txt")

show_usage() {
    echo "Cloud-Init Files Comparison Script"
    echo ""
    echo "Usage: $0 [OPTIONS] FILESYSTEM1 FILESYSTEM2"
    echo ""
    echo "Arguments:"
    echo "  FILESYSTEM1    First filesystem to compare (e.g., /dev/sda1 or /mnt/disk1)"
    echo "  FILESYSTEM2    Second filesystem to compare (e.g., /dev/mmcblk0p1 or /boot/firmware)"
    echo ""
    echo "Options:"
    echo "  --detailed, -d    Show detailed diff output for differences"
    echo "  --summary, -s     Show only summary (default)"
    echo "  --files FILE,...  Compare specific files (comma-separated)"
    echo "  --help, -h        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 /dev/sda1 /dev/mmcblk0p1                    # Compare two block devices"
    echo "  $0 /mnt/disk1 /boot/firmware                   # Compare mounted filesystems"
    echo "  $0 -d /dev/sda1 /boot/firmware                 # Detailed comparison"
    echo "  $0 --files user-data,meta-data /dev/sda1 /boot/firmware"
    echo ""
    echo "Note: Block devices will be temporarily mounted if not already mounted"
}

# Function to check if a path is a block device
is_block_device() {
    [[ -b "$1" ]]
}

# Function to check if a filesystem is already mounted
get_mount_point() {
    local device="$1"
    if is_block_device "$device"; then
        mount | grep "^$device " | awk '{print $3}' | head -1 || true
    else
        echo "$device"
    fi
}

# Function to mount a filesystem temporarily
mount_filesystem() {
    local device="$1"
    local mount_point
    
    if is_block_device "$device"; then
        # Check if already mounted
        mount_point=$(get_mount_point "$device")
        if [[ -n "$mount_point" ]]; then
            echo "$mount_point"
            return 0
        fi
        
        # Create temporary mount point
        mount_point=$(mktemp -d)
        if ! sudo mount "$device" "$mount_point" 2>/dev/null; then
            print_error "Failed to mount $device"
            rmdir "$mount_point" 2>/dev/null || true
            return 1
        fi
        echo "$mount_point"
    else
        # Assume it's already a mount point or directory
        if [[ -d "$device" ]]; then
            echo "$device"
        else
            print_error "Path does not exist: $device"
            return 1
        fi
    fi
}

# Function to unmount a filesystem if we mounted it
unmount_filesystem() {
    local device="$1"
    local mount_point="$2"
    local was_mounted="$3"
    
    if is_block_device "$device" && [[ "$was_mounted" == "false" ]]; then
        sudo umount "$mount_point" 2>/dev/null || true
        rmdir "$mount_point" 2>/dev/null || true
    fi
}

# Function to compare file sizes
compare_file_sizes() {
    local file1="$1"
    local file2="$2"
    local name="$3"
    
    if [[ -f "$file1" && -f "$file2" ]]; then
        local size1=$(stat -c%s "$file1" 2>/dev/null || echo "0")
        local size2=$(stat -c%s "$file2" 2>/dev/null || echo "0")
        
        if [[ "$size1" -eq "$size2" ]]; then
            echo -e "  ${GREEN}✓${NC} $name: ${size1} bytes (identical)"
        else
            echo -e "  ${YELLOW}△${NC} $name: ${size1} vs ${size2} bytes (different)"
        fi
    elif [[ -f "$file1" ]]; then
        local size1=$(stat -c%s "$file1" 2>/dev/null || echo "0")
        echo -e "  ${RED}✗${NC} $name: ${size1} bytes vs MISSING"
    elif [[ -f "$file2" ]]; then
        local size2=$(stat -c%s "$file2" 2>/dev/null || echo "0")  
        echo -e "  ${RED}✗${NC} $name: MISSING vs ${size2} bytes"
    else
        echo -e "  ${RED}✗${NC} $name: MISSING in both filesystems"
    fi
}

# Function to compare file contents
compare_file_contents() {
    local file1="$1"
    local file2="$2"
    local name="$3"
    local detailed="$4"
    
    if [[ -f "$file1" && -f "$file2" ]]; then
        if cmp -s "$file1" "$file2"; then
            echo -e "  ${GREEN}✓${NC} $name: Files are identical"
        else
            echo -e "  ${YELLOW}△${NC} $name: Files differ"
            if [[ "$detailed" == "true" ]]; then
                echo ""
                print_subheader "Differences in $name"
                diff -u "$file1" "$file2" | head -50 || true
                echo ""
            fi
        fi
    elif [[ -f "$file1" ]]; then
        echo -e "  ${RED}✗${NC} $name: Only exists in first filesystem"
        if [[ "$detailed" == "true" ]]; then
            echo ""
            print_subheader "Content of $name (first filesystem only)"
            head -20 "$file1" || true
            echo ""
        fi
    elif [[ -f "$file2" ]]; then
        echo -e "  ${RED}✗${NC} $name: Only exists in second filesystem"
        if [[ "$detailed" == "true" ]]; then
            echo ""
            print_subheader "Content of $name (second filesystem only)"
            head -20 "$file2" || true
            echo ""
        fi
    else
        echo -e "  ${RED}✗${NC} $name: Missing in both filesystems"
    fi
}

# Function to show file contents side by side
show_file_comparison() {
    local file1="$1"
    local file2="$2" 
    local name="$3"
    local fs1_name="$4"
    local fs2_name="$5"
    
    print_subheader "$name Comparison"
    
    if [[ -f "$file1" && -f "$file2" ]]; then
        echo -e "${CYAN}$fs1_name${NC} | ${MAGENTA}$fs2_name${NC}"
        echo "$(printf '%*s' 40 | tr ' ' '-') | $(printf '%*s' 40 | tr ' ' '-')"
        
        # Show first 15 lines of each file side by side
        paste <(head -15 "$file1" | cut -c1-38 | sed 's/$/                                      /' | cut -c1-38) \
              <(head -15 "$file2" | cut -c1-38) | \
        while IFS=$'\t' read -r left right; do
            echo -e "${left} | ${right}"
        done
        echo ""
    elif [[ -f "$file1" ]]; then
        echo -e "${CYAN}$fs1_name only:${NC}"
        head -15 "$file1"
        echo ""
    elif [[ -f "$file2" ]]; then
        echo -e "${MAGENTA}$fs2_name only:${NC}"
        head -15 "$file2"
        echo ""
    else
        echo "File not found in either filesystem"
        echo ""
    fi
}

# Main comparison function
compare_cloud_init_files() {
    local fs1="$1"
    local fs2="$2"
    local detailed="$3"
    local files_to_compare=("${@:4}")
    
    print_header "Cloud-Init Files Comparison"
    print_info "Filesystem 1: $fs1"
    print_info "Filesystem 2: $fs2"
    echo ""
    
    # Mount filesystems
    local mount1 mount2 was_mounted1="true" was_mounted2="true"
    
    mount1=$(get_mount_point "$fs1")
    if [[ -z "$mount1" ]]; then
        mount1=$(mount_filesystem "$fs1")
        was_mounted1="false"
    fi
    
    mount2=$(get_mount_point "$fs2")
    if [[ -z "$mount2" ]]; then
        mount2=$(mount_filesystem "$fs2")
        was_mounted2="false"
    fi
    
    if [[ -z "$mount1" || -z "$mount2" ]]; then
        print_error "Failed to mount one or both filesystems"
        return 1
    fi
    
    print_info "Mounted at: $mount1 and $mount2"
    echo ""
    
    # Compare files
    print_header "File Size Comparison"
    for file in "${files_to_compare[@]}"; do
        compare_file_sizes "$mount1/$file" "$mount2/$file" "$file"
    done
    echo ""
    
    print_header "Content Comparison"
    for file in "${files_to_compare[@]}"; do
        compare_file_contents "$mount1/$file" "$mount2/$file" "$file" "$detailed"
    done
    
    # Show detailed side-by-side comparison if requested
    if [[ "$detailed" == "true" ]]; then
        echo ""
        print_header "Detailed File Contents"
        for file in "${files_to_compare[@]}"; do
            if [[ -f "$mount1/$file" || -f "$mount2/$file" ]]; then
                show_file_comparison "$mount1/$file" "$mount2/$file" "$file" \
                                   "$(basename "$fs1")" "$(basename "$fs2")"
            fi
        done
    fi
    
    # Cleanup
    unmount_filesystem "$fs1" "$mount1" "$was_mounted1"
    unmount_filesystem "$fs2" "$mount2" "$was_mounted2"
    
    print_success "Comparison completed"
}

# Parse command line arguments
detailed="false"
files_to_compare=("${CLOUD_INIT_FILES[@]}")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --detailed|-d)
            detailed="true"
            shift
            ;;
        --summary|-s)
            detailed="false"
            shift
            ;;
        --files)
            if [[ -z "${2:-}" ]]; then
                print_error "--files requires a comma-separated list of files"
                exit 1
            fi
            IFS=',' read -ra files_to_compare <<< "$2"
            shift 2
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
            break
            ;;
    esac
done

# Check required arguments
if [[ $# -lt 2 ]]; then
    print_error "Two filesystems are required for comparison"
    show_usage
    exit 1
fi

fs1="$1"
fs2="$2"

# Validate filesystems
for fs in "$fs1" "$fs2"; do
    if ! is_block_device "$fs" && ! [[ -d "$fs" ]]; then
        print_error "Invalid filesystem: $fs (must be a block device or directory)"
        exit 1
    fi
done

# Run comparison
compare_cloud_init_files "$fs1" "$fs2" "$detailed" "${files_to_compare[@]}"