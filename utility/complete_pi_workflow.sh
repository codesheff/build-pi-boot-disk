#!/bin/bash

# Complete Pi Disk Workflow Script
# Downloads Ubuntu image, extracts customizations, and creates dual-partition disks
# Usage: ./complete_pi_workflow.sh [target_device] [ubuntu_version]

set -e

# Configuration
DEFAULT_TARGET_DEVICE="/dev/sda"
DEFAULT_UBUNTU_VERSION="24.04"  # LTS version for stability
SCRIPT_DIR="$(dirname "$0")"

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

# Function to show workflow steps
show_workflow() {
    print_status "Complete Pi Disk Creation Workflow"
    echo
    echo "This script will:"
    echo "  1. Download official Ubuntu Server image"
    echo "  2. Extract current system customizations"
    echo "  3. Create dual-partition Pi disk with customizations"
    echo "  4. Install reset script for factory reset capability"
    echo
    print_status "Benefits:"
    echo "  ✓ Uses official Ubuntu images (more secure and up-to-date)"
    echo "  ✓ Preserves your user accounts, SSH keys, and network settings"
    echo "  ✓ Creates backup partition for system reset functionality"
    echo "  ✓ Maintains all your customizations and configurations"
    echo
}

# Function to run workflow step
run_step() {
    local step_name="$1"
    local script_name="$2"
    shift 2
    local args="$@"
    
    print_status "Step: $step_name"
    print_status "Running: $script_name $args"
    
    if ! "$SCRIPT_DIR/$script_name" $args; then
        print_error "Failed at step: $step_name"
        exit 1
    fi
    
    print_success "Completed: $step_name"
    echo
}

# Main function
main() {
    local target_device="${1:-$DEFAULT_TARGET_DEVICE}"
    local ubuntu_version="${2:-$DEFAULT_UBUNTU_VERSION}"
    
    print_status "Complete Pi Disk Workflow Starting..."
    print_status "Target device: $target_device"
    print_status "Ubuntu version: $ubuntu_version"
    
    # Pre-flight checks
    check_root
    show_workflow
    
    # Confirmation
    read -p "Do you want to continue with the complete workflow? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Workflow cancelled by user"
        exit 0
    fi
    
    # Step 1: Download Ubuntu image
    run_step "Download Ubuntu Image" "download_ubuntu_image.sh" "$ubuntu_version"
    
    # Step 2: Extract customizations
    run_step "Extract System Customizations" "extract_customizations.sh"
    
    # Step 3: Create Pi disk
    local ubuntu_image=$(ls -t /home/pi/ubuntu-images/*.img 2>/dev/null | head -1)
    if [[ ! -f "$ubuntu_image" ]]; then
        print_error "No Ubuntu image found after download"
        exit 1
    fi
    
    run_step "Create Dual-Partition Pi Disk" "create_pi_disk.sh" "$ubuntu_image" "$target_device"
    
    # Final success message
    print_success "Complete Pi Disk Workflow Finished!"
    echo
    print_status "Your Pi disk is ready with:"
    echo "  ✓ Latest Ubuntu $ubuntu_version Server"
    echo "  ✓ Your user accounts and SSH keys"
    echo "  ✓ Your network configuration"
    echo "  ✓ Your system customizations"
    echo "  ✓ Factory reset capability (sudo pi-reset.sh)"
    echo
    print_status "The disk can now be used in any Raspberry Pi!"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [TARGET_DEVICE] [UBUNTU_VERSION]"
    echo ""
    echo "Arguments:"
    echo "  TARGET_DEVICE   Target device to write to (default: $DEFAULT_TARGET_DEVICE)"
    echo "  UBUNTU_VERSION  Ubuntu version to download (default: $DEFAULT_UBUNTU_VERSION)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Use defaults (/dev/sda, Ubuntu 24.04 LTS)"
    echo "  $0 /dev/sdb         # Use /dev/sdb with Ubuntu 24.04 LTS"
    echo "  $0 /dev/sdc 25.10   # Use /dev/sdc with Ubuntu 25.10"
    echo ""
    echo "Available Ubuntu versions:"
    echo "  24.04   - LTS (recommended for production)"
    echo "  24.10   - Latest stable"
    echo "  25.10   - Current development"
    echo ""
    echo "This workflow script will:"
    echo "  1. Download the official Ubuntu Server image"
    echo "  2. Extract your current system customizations"
    echo "  3. Create a dual-partition Pi disk with all settings preserved"
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