#!/bin/bash

# Raspberry Pi Ubuntu Server Image Downloader
# Downloads official Ubuntu Server images for Raspberry Pi from Canonical

set -e

# Configuration
IMAGES_DIR="$(dirname "$0")/../images"
UBUNTU_RELEASES_URL="https://cdimage.ubuntu.com/releases"
TEMP_DIR="/tmp/pi-image-download"

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
Usage: $0 [OPTIONS]

Downloads official Ubuntu Server images for Raspberry Pi

OPTIONS:
    -r, --release VERSION    Ubuntu release version (default: 22.04)
    -a, --arch ARCH         Architecture (default: arm64)
    -t, --type TYPE         Pi type: pi4 or pi5 (default: pi4)
    -f, --force             Force re-download even if image exists
    -l, --list              List available releases
    -h, --help              Show this help message

EXAMPLES:
    $0                      # Download Ubuntu 22.04 LTS for Pi 4
    $0 -r 24.04 -t pi5      # Download Ubuntu 24.04 LTS for Pi 5
    $0 -l                   # List available releases

EOF
}

# Function to list available releases
list_releases() {
    log_info "Fetching available Ubuntu releases for Raspberry Pi..."
    
    # Common LTS releases that support Raspberry Pi
    cat << EOF
Available Ubuntu Server releases for Raspberry Pi:

LTS Releases (Recommended):
  20.04.6 - Ubuntu 20.04.6 LTS (Focal Fossa)
  22.04.5 - Ubuntu 22.04.5 LTS (Jammy Jellyfish) [Recommended]
  24.04.1 - Ubuntu 24.04.1 LTS (Noble Numbat)

Supported Pi Models:
  pi4 - Raspberry Pi 4 and Pi 400
  pi5 - Raspberry Pi 5

Architecture:
  arm64 - 64-bit ARM (recommended for better performance)

Note: Use the version number (e.g., 22.04) with the -r flag.
EOF
}

# Function to get download URL
get_download_url() {
    local release="$1"
    local arch="$2"
    local pi_type="$3"
    
    # Map pi types to Ubuntu naming
    local ubuntu_type
    case "$pi_type" in
        "pi4") ubuntu_type="raspi" ;;
        "pi5") ubuntu_type="raspi" ;;
        *) log_error "Unsupported Pi type: $pi_type"; exit 1 ;;
    esac
    
    # Construct URL based on release
    local base_url="${UBUNTU_RELEASES_URL}/${release}/release"
    local filename="ubuntu-${release}-preinstalled-server-${arch}+${ubuntu_type}.img.xz"
    
    echo "${base_url}/${filename}"
}

# Function to verify checksums
verify_checksum() {
    local file="$1"
    local checksum_url="$2"
    
    log_info "Verifying checksum for $(basename "$file")..."
    
    # Download SHA256SUMS file
    local checksum_file="${TEMP_DIR}/SHA256SUMS"
    if wget -q -O "$checksum_file" "${checksum_url%/*}/SHA256SUMS"; then
        # Extract expected checksum for our file
        local expected_sum=$(grep "$(basename "$file")" "$checksum_file" | cut -d' ' -f1)
        
        if [ -n "$expected_sum" ]; then
            # Calculate actual checksum
            local actual_sum=$(sha256sum "$file" | cut -d' ' -f1)
            
            if [ "$expected_sum" = "$actual_sum" ]; then
                log_success "Checksum verification passed"
                return 0
            else
                log_error "Checksum verification failed!"
                log_error "Expected: $expected_sum"
                log_error "Actual:   $actual_sum"
                return 1
            fi
        else
            log_warning "Could not find checksum for file in SHA256SUMS"
            return 0
        fi
    else
        log_warning "Could not download SHA256SUMS file for verification"
        return 0
    fi
}

# Function to download image
download_image() {
    local release="$1"
    local arch="$2"
    local pi_type="$3"
    local force="$4"
    
    # Create directories
    mkdir -p "$IMAGES_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Get download URL
    local download_url=$(get_download_url "$release" "$arch" "$pi_type")
    local filename=$(basename "$download_url")
    local output_file="$IMAGES_DIR/$filename"
    local extracted_file="${output_file%.xz}"
    
    log_info "Release: Ubuntu $release"
    log_info "Architecture: $arch"
    log_info "Pi Type: $pi_type"
    log_info "Download URL: $download_url"
    
    # Check if image already exists
    if [ -f "$extracted_file" ] && [ "$force" != "true" ]; then
        log_warning "Image already exists: $extracted_file"
        log_info "Use --force to re-download"
        return 0
    fi
    
    # Download compressed image
    log_info "Downloading $filename..."
    if wget -c -O "$output_file" "$download_url"; then
        log_success "Download completed: $filename"
        
        # Verify checksum
        verify_checksum "$output_file" "$download_url"
        
        # Extract image
        if [ -f "$output_file" ]; then
            log_info "Extracting image..."
            if xz -d -k "$output_file"; then
                log_success "Image extracted: $(basename "$extracted_file")"
                
                # Remove compressed file to save space
                rm "$output_file"
                log_info "Removed compressed file to save space"
                
                # Show image info
                log_info "Image ready: $extracted_file"
                log_info "Size: $(du -h "$extracted_file" | cut -f1)"
            else
                log_error "Failed to extract image"
                return 1
            fi
        fi
    else
        log_error "Failed to download image"
        log_error "Please check your internet connection and try again"
        return 1
    fi
}

# Main function
main() {
    local release="22.04"
    local arch="arm64"
    local pi_type="pi4"
    local force="false"
    local list_only="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--release)
                release="$2"
                shift 2
                ;;
            -a|--arch)
                arch="$2"
                shift 2
                ;;
            -t|--type)
                pi_type="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -l|--list)
                list_only="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check if we should just list releases
    if [ "$list_only" = "true" ]; then
        list_releases
        exit 0
    fi
    
    # Validate inputs
    if [ "$arch" != "arm64" ]; then
        log_error "Only arm64 architecture is currently supported"
        exit 1
    fi
    
    if [ "$pi_type" != "pi4" ] && [ "$pi_type" != "pi5" ]; then
        log_error "Pi type must be 'pi4' or 'pi5'"
        exit 1
    fi
    
    # Check dependencies
    for cmd in wget xz sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            log_error "Please install: sudo apt update && sudo apt install wget xz-utils coreutils"
            exit 1
        fi
    done
    
    log_info "Starting Ubuntu Server image download for Raspberry Pi"
    
    # Download the image
    if download_image "$release" "$arch" "$pi_type" "$force"; then
        log_success "Ubuntu Server image download completed successfully!"
        log_info "Image location: $IMAGES_DIR"
        log_info "Next step: Run ./scripts/create-boot-disk.sh to create your boot disk"
    else
        log_error "Failed to download Ubuntu Server image"
        exit 1
    fi
}

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Run main function
main "$@"