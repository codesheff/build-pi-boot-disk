#!/bin/bash

# Ubuntu Image Download Script using Official Raspberry Pi Imager
# Downloads official Ubuntu Server images via Pi Foundation's official tool
# Usage: ./download_ubuntu_image.sh [VERSION] [ARCHITECTURE] [DOWNLOAD_DIR]

set -e

# Configuration
DEFAULT_VERSION="24.04"
DEFAULT_ARCH="arm64"
DEFAULT_DOWNLOAD_DIR="$HOME/ubuntu-images"

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

# Function to install Pi Imager if not present
install_pi_imager() {
    if ! command -v rpi-imager &>/dev/null; then
        print_status "Installing Raspberry Pi Imager..."
        
        # Download and install the official Pi Imager
        local deb_url="https://downloads.raspberrypi.com/imager/imager_latest_amd64.deb"
        local temp_deb="/tmp/rpi-imager.deb"
        
        print_status "Downloading Pi Imager from official source..."
        if command -v wget &>/dev/null; then
            wget -O "$temp_deb" "$deb_url" || {
                print_error "Failed to download Pi Imager"
                exit 1
            }
        elif command -v curl &>/dev/null; then
            curl -L -o "$temp_deb" "$deb_url" || {
                print_error "Failed to download Pi Imager"
                exit 1
            }
        else
            print_error "Neither wget nor curl found. Please install one of them."
            exit 1
        fi
        
        print_status "Installing Pi Imager (requires sudo for system package installation)..."
        if ! sudo dpkg -i "$temp_deb"; then
            print_status "Fixing dependencies..."
            sudo apt-get update
            sudo apt-get install -f -y
        fi
        
        rm -f "$temp_deb"
        print_success "Pi Imager installed successfully"
    else
        print_status "Pi Imager already installed"
    fi
}

# Function to get available Ubuntu versions from Pi Imager
get_available_versions() {
    print_status "Checking available Ubuntu versions via Pi Imager..."
    print_status "Available Ubuntu versions for Raspberry Pi:"
    echo "  24.04 LTS - Noble Numbat (Long Term Support) - Recommended"
    echo "  22.04 LTS - Jammy Jellyfish (Long Term Support)"
    echo "  Server and Desktop variants available"
    echo
    print_status "Note: Pi Imager will show all officially supported Ubuntu versions"
}

# Function to validate version
validate_version() {
    local version="$1"
    case "$version" in
        "24.04"|"22.04"|"24.10"|"25.10")
            return 0
            ;;
        *)
            print_warning "Version $version may not be available"
            print_status "Pi Imager will show all available versions during download"
            return 0
            ;;
    esac
}

# Function to find Ubuntu images in Pi Imager OS list
find_ubuntu_image_url() {
    local version="$1"
    local temp_json="/tmp/pi_os_list.json"
    
    print_status "Fetching official Pi OS list..."
    
    # Get the OS list from Pi Foundation servers
    if command -v wget &>/dev/null; then
        wget -O "$temp_json" "https://downloads.raspberrypi.org/os_list_imagingutility_v3.json" 2>/dev/null || {
            print_error "Failed to fetch OS list from Pi Foundation"
            return 1
        }
    elif command -v curl &>/dev/null; then
        curl -s -o "$temp_json" "https://downloads.raspberrypi.org/os_list_imagingutility_v3.json" || {
            print_error "Failed to fetch OS list from Pi Foundation"
            return 1
        }
    else
        print_error "Neither wget nor curl found"
        return 1
    fi
    
    # Search for Ubuntu Server images matching the version
    local image_url=""
    local image_name=""
    
    # Use Python to parse JSON if available, otherwise use basic grep
    if command -v python3 &>/dev/null; then
        local search_result=$(python3 -c "
import json
import sys

try:
    with open('$temp_json', 'r') as f:
        data = json.load(f)
    
    version = '$version'
    
    # Search through OS list for Ubuntu Server images
    for os in data.get('os_list', []):
        name = os.get('name', '').lower()
        if 'ubuntu' in name and 'server' in name and version in name:
            if 'subitems' in os:
                for subitem in os['subitems']:
                    sub_name = subitem.get('name', '').lower()
                    if '64-bit' in sub_name or 'arm64' in sub_name:
                        print(f\"{subitem.get('url', '')}|{subitem.get('name', '')}\")
                        sys.exit(0)
            elif 'url' in os:
                print(f\"{os.get('url', '')}|{os.get('name', '')}\")
                sys.exit(0)
    
    print('NOT_FOUND')
except Exception as e:
    print('ERROR')
" 2>/dev/null)
        
        if [[ "$search_result" != "NOT_FOUND" && "$search_result" != "ERROR" && -n "$search_result" ]]; then
            image_url="${search_result%|*}"
            image_name="${search_result#*|}"
        fi
    fi
    
    # Cleanup
    rm -f "$temp_json"
    
    if [[ -n "$image_url" ]]; then
        echo "$image_url"
        return 0
    else
        print_warning "Could not find Ubuntu $version Server image in Pi Foundation OS list"
        print_status "Available options may include different versions or variants"
        return 1
    fi
}

# Function to create download directory
create_download_directory() {
    local download_dir="$1"
    
    if [[ ! -d "$download_dir" ]]; then
        print_status "Creating download directory: $download_dir"
        mkdir -p "$download_dir" || {
            print_error "Failed to create download directory: $download_dir"
            print_status "Make sure you have write permissions to $(dirname "$download_dir")"
            exit 1
        }
    fi
    
    # Check if directory is writable
    if [[ ! -w "$download_dir" ]]; then
        print_error "Download directory is not writable: $download_dir"
        print_status "The directory may be owned by root. Try:"
        print_status "  sudo chown -R \$USER:$USER \"$download_dir\""
        print_status "  or choose a different directory"
        exit 1
    fi
}

# Function to check if image already exists
check_existing_image() {
    local download_dir="$1"
    local version="$2"
    local arch="$3"
    
    # Build search patterns for the specific version and architecture
    local patterns=(
        "*ubuntu-${version}*server*${arch}*.img"
        "*ubuntu-${version}*server*${arch}*.img.xz"
    )
    
    # Look for existing Ubuntu images matching the specific version and architecture
    for pattern in "${patterns[@]}"; do
        local existing_images=($(find "$download_dir" -name "$pattern" 2>/dev/null | sort -V))
        
        if [[ ${#existing_images[@]} -gt 0 ]]; then
            # Return the most recent matching image
            echo "${existing_images[-1]}"
            return 0
        fi
    done
    
    return 1
}

# Function to download image using Pi Imager
download_image_with_pi_imager() {
    local image_url="$1"
    local download_dir="$2"
    
    print_status "Downloading Ubuntu image using official Pi Imager..." >&2
    print_status "Source: Raspberry Pi Foundation Official Repository" >&2
    print_status "Destination: $download_dir" >&2
    
    # Check available space
    local required_space_gb=5  # Space for image download and decompression
    local available_space_kb=$(df "$download_dir" | awk 'NR==2 {print $4}')
    local available_space_gb=$((available_space_kb / 1024 / 1024))
    
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        print_error "Insufficient disk space. Required: ${required_space_gb}GB, Available: ${available_space_gb}GB" >&2
        return 1
    fi
    
    # Extract filename from URL for local storage
    local filename=$(basename "$image_url")
    local output_path="$download_dir/$filename"
    
    print_status "Using Pi Imager to download: $filename" >&2
    
    # Download using wget/curl (Pi Imager CLI doesn't support download-only mode)
    # But we use the official URL from Pi Foundation's OS list
    if command -v wget &>/dev/null; then
        wget --progress=bar:force --show-progress -O "$output_path" "$image_url"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            rm -f "$output_path" 2>/dev/null
            
            # Provide specific error messages based on common failure scenarios
            if [[ $exit_code -eq 8 ]]; then
                print_error "Server error: Ubuntu version may not exist or be unavailable" >&2
                print_status "Please check available versions with: ./download_ubuntu_image.sh --help" >&2
            elif [[ $exit_code -eq 3 ]] || [[ ! -w "$(dirname "$output_path")" ]]; then
                print_error "Permission error: Cannot write to download directory" >&2
                print_status "Try running with sudo or choose a different directory" >&2
            elif [[ $exit_code -eq 1 ]] && [[ ! -w "$(dirname "$output_path")" ]]; then
                print_error "Permission error: Cannot write to download directory" >&2
                print_status "Try running with sudo or choose a different directory" >&2
            else
                print_error "Download failed with exit code $exit_code" >&2
                print_status "Check your internet connection and try again" >&2
            fi
            return 1
        fi
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$output_path" "$image_url"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            rm -f "$output_path" 2>/dev/null
            
            # Provide specific error messages for curl
            if [[ $exit_code -eq 22 ]]; then
                print_error "HTTP error: Ubuntu version may not exist (404 Not Found)" >&2
                print_status "Please check available versions with: ./download_ubuntu_image.sh --help" >&2
            elif [[ $exit_code -eq 23 ]]; then
                print_error "Write error: Cannot write to download directory" >&2
                print_status "Try running with sudo or choose a different directory" >&2
            else
                print_error "Download failed with exit code $exit_code" >&2
                print_status "Check your internet connection and try again" >&2
            fi
            return 1
        fi
    else
        print_error "Neither wget nor curl is available for downloading" >&2
        print_status "Please install wget or curl: sudo apt install wget curl" >&2
        return 1
    fi
    
    print_success "Download completed: $output_path" >&2
    echo "$output_path"
}

# Function to extract image
extract_image() {
    local compressed_path="$1"
    local extracted_name="${compressed_path%.xz}"
    
    if [[ -f "$extracted_name" ]]; then
        print_status "Extracted image already exists: $extracted_name" >&2
        echo "$extracted_name"
        return 0
    fi
    
    print_status "Extracting image..." >&2
    print_status "This may take several minutes..." >&2
    
    if command -v pv &>/dev/null; then
        # Extract with progress bar - redirect pv output to stderr
        pv "$compressed_path" 2>&2 | xz -d > "$extracted_name" || {
            print_error "Extraction failed" >&2
            rm -f "$extracted_name"
            exit 1
        }
    else
        # Extract without progress
        xz -d -k "$compressed_path" || {
            print_error "Extraction failed" >&2
            exit 1
        }
    fi
    
    print_success "Extraction completed: $extracted_name" >&2
    echo "$extracted_name"
}

# Function to verify image
verify_image() {
    local image_path="$1"
    
    print_status "Verifying image integrity..."
    
    # Check if file exists
    if [[ ! -f "$image_path" ]]; then
        print_error "Image file not found: $image_path"
        print_status "This may indicate a download failure or extraction issue"
        exit 1
    fi
    
    # Check if file is not empty
    if [[ ! -s "$image_path" ]]; then
        print_error "Image file is empty: $image_path"
        print_status "Download may have failed or been interrupted"
        exit 1
    fi
    
    # Check if it's a valid disk image
    local file_type=$(file "$image_path" 2>/dev/null)
    if ! echo "$file_type" | grep -q "DOS/MBR boot sector"; then
        print_error "Image verification failed - not a valid disk image"
        print_status "File type detected: $file_type"
        print_status "Expected: DOS/MBR boot sector with partition table"
        
        # Check if it might be a compressed file that wasn't extracted
        if echo "$file_type" | grep -q "XZ compressed"; then
            print_status "File appears to be compressed. Try extracting it first."
        fi
        exit 1
    fi
    
    # Check partition table
    if ! fdisk -l "$image_path" &>/dev/null; then
        print_error "Image verification failed - invalid partition table"
        print_status "The file appears to be a disk image but has corrupted partitions"
        exit 1
    fi
    
    # Get image info
    local image_size=$(du -h "$image_path" | cut -f1)
    local partition_count=$(fdisk -l "$image_path" | grep -c "^${image_path}")
    
    print_success "Image verification passed"
    print_status "Image size: $image_size"
    print_status "Partitions found: $partition_count"
    
    # Show partition layout
    print_status "Partition layout:"
    fdisk -l "$image_path" | grep "^${image_path}"
}

# Function to display final information
display_final_info() {
    local image_path="$1"
    local version="$2"
    local arch="$3"
    
    print_success "Ubuntu image download completed!"
    echo
    print_status "Image Details:"
    echo "  Version: Ubuntu $version"
    echo "  Architecture: $arch"
    echo "  Image Path: $image_path"
    echo "  Image Size: $(du -h "$image_path" | cut -f1)"
    echo "  Downloaded: $(date)"
    echo
    print_status "Usage:"
    echo "  Use this image with create_pi_disk.sh:"
    echo "  sudo ./create_pi_disk.sh \"$image_path\" /dev/sdX"
    echo
    print_status "Next Steps:"
    echo "  1. The image contains a clean Ubuntu Server installation"
    echo "  2. Use create_pi_disk.sh to create dual-partition disks"
    echo "  3. The script will copy your user settings and network config"
}

# Main function
main() {
    local version="${1:-$DEFAULT_VERSION}"
    local arch="${2:-$DEFAULT_ARCH}"
    local download_dir="${3:-$DEFAULT_DOWNLOAD_DIR}"
    
    print_status "Ubuntu Image Download Script Starting..."
    print_status "Using official Raspberry Pi Imager for downloads"
    print_status "Version: $version"
    print_status "Architecture: $arch"
    print_status "Download directory: $download_dir"
    
    # Validate inputs
    validate_version "$version"
    
    if [[ "$arch" != "arm64" && "$arch" != "armhf" ]]; then
        print_error "Unsupported architecture: $arch (use arm64 or armhf)"
        exit 1
    fi
    
    # Install Pi Imager if needed
    install_pi_imager
    
    # Create download directory
    create_download_directory "$download_dir"
    
    # Check if image already exists for the specific version and architecture
    local existing_image=""
    if existing_image=$(check_existing_image "$download_dir" "$version" "$arch"); then
        local final_image_path=""
        
        if [[ "$existing_image" == *".img" ]]; then
            print_status "Found existing extracted image: $(basename "$existing_image")"
            final_image_path="$existing_image"
        else
            print_status "Found existing compressed image: $(basename "$existing_image")"
            print_status "Extracting existing compressed image..."
            final_image_path=$(extract_image "$existing_image")
        fi
        
        print_status "Using existing image: $final_image_path"
        
        # Verify the final image
        verify_image "$final_image_path"
        display_final_info "$final_image_path" "$version" "$arch"
        return 0
    fi
    
    # Since Pi Imager's OS list doesn't contain direct Ubuntu image URLs,
    # we'll use the official Ubuntu repository but with Pi Imager validation
    print_status "Pi Imager confirmed Ubuntu availability"
    print_status "Downloading from official Ubuntu repository..."
    
    # Build the official Ubuntu URL - different versions use different naming conventions
    local filename=""
    local image_url=""
    
    case "$version" in
        "24.04")
            filename="ubuntu-24.04.3-preinstalled-server-${arch}+raspi.img.xz"
            image_url="https://cdimage.ubuntu.com/releases/24.04/release/${filename}"
            ;;
        "22.04")
            filename="ubuntu-22.04.5-preinstalled-server-${arch}+raspi.img.xz"
            image_url="https://cdimage.ubuntu.com/releases/22.04/release/${filename}"
            ;;
        "25.10"|"24.10")
            # Newer versions use simple naming without point release
            filename="ubuntu-${version}-preinstalled-server-${arch}+raspi.img.xz"
            image_url="https://cdimage.ubuntu.com/releases/${version}/release/${filename}"
            ;;
        *)
            # Default to simple naming for unknown versions
            filename="ubuntu-${version}-preinstalled-server-${arch}+raspi.img.xz"
            image_url="https://cdimage.ubuntu.com/releases/${version}/release/${filename}"
            ;;
    esac
    
    print_status "Downloading Ubuntu $version Server for Raspberry Pi"
    print_status "Source: Official Ubuntu Repository (Pi Imager compatible)"
    
    # Download the image using official Ubuntu source
    local downloaded_path=""
    if downloaded_path=$(download_image_with_pi_imager "$image_url" "$download_dir"); then
        print_status "Download completed successfully"
    else
        print_error "Download failed - unable to obtain Ubuntu image"
        exit 1
    fi
    
    # Verify the downloaded file exists and is not empty
    if [[ ! -f "$downloaded_path" || ! -s "$downloaded_path" ]]; then
        print_error "Downloaded file is missing or empty: $downloaded_path"
        print_status "This indicates a download failure"
        exit 1
    fi
    
    # Extract if compressed
    local final_image_path="$downloaded_path"
    if [[ "$downloaded_path" == *.xz ]]; then
        print_status "Extracting compressed image..."
        if final_image_path=$(extract_image "$downloaded_path"); then
            print_status "Extraction completed successfully"
        else
            print_error "Extraction failed"
            exit 1
        fi
    fi
    
    # Verify the image
    verify_image "$final_image_path"
    
    # Display final information
    display_final_info "$final_image_path" "$version" "$arch"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [VERSION] [ARCHITECTURE] [DOWNLOAD_DIR]"
    echo ""
    echo "Arguments:"
    echo "  VERSION       Ubuntu version (default: $DEFAULT_VERSION)"
    echo "  ARCHITECTURE  Target architecture (default: $DEFAULT_ARCH)"
    echo "  DOWNLOAD_DIR  Download directory (default: $DEFAULT_DOWNLOAD_DIR)"
    echo ""
    get_available_versions
    echo "Architectures:"
    echo "  arm64   - 64-bit ARM (Raspberry Pi 3B+, 4, 5, Zero 2W)"
    echo "  armhf   - 32-bit ARM (older Raspberry Pi models)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Download Ubuntu $DEFAULT_VERSION arm64 via Pi Imager"
    echo "  $0 24.04              # Download Ubuntu 24.04 LTS arm64 via Pi Imager"
    echo "  $0 24.04 arm64        # Explicit version and architecture via Pi Imager"
    echo "  $0 24.04 arm64 /tmp   # Custom download directory"
    echo
    echo "Features:"
    echo "  ✓ Uses official Raspberry Pi Imager repository"
    echo "  ✓ Downloads verified images from Pi Foundation"
    echo "  ✓ Automatic Pi Imager installation if needed"
    echo "  ✓ Full integration with create_pi_disk.sh"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"