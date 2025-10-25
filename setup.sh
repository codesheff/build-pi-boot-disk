#!/bin/bash

# Quick Setup Script for Raspberry Pi Boot Disk Project
# Installs dependencies and prepares the environment

set -e

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

# Function to detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        elif [ -f /etc/arch-release ]; then
            echo "arch"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to install dependencies on Debian/Ubuntu
install_debian_deps() {
    log_info "Installing dependencies for Debian/Ubuntu..."
    
    sudo apt update
    sudo apt install -y \
        wget \
        xz-utils \
        parted \
        dosfstools \
        e2fsprogs \
        rsync \
        tar \
        coreutils \
        util-linux \
        mount \
        pigz
    
    log_success "Dependencies installed successfully"
}

# Function to install dependencies on macOS
install_macos_deps() {
    log_info "Installing dependencies for macOS..."
    
    # Check if Homebrew is installed
    if ! command -v brew >/dev/null 2>&1; then
        log_warning "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    brew install wget xz parted coreutils pigz
    
    log_success "Dependencies installed successfully"
    log_warning "Note: Some operations may require additional tools on macOS"
}

# Function to install dependencies on Red Hat/CentOS/Fedora
install_redhat_deps() {
    log_info "Installing dependencies for Red Hat/CentOS/Fedora..."
    
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y wget xz parted dosfstools e2fsprogs rsync tar util-linux pigz
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y wget xz parted dosfstools e2fsprogs rsync tar util-linux pigz
    else
        log_error "Neither dnf nor yum found"
        exit 1
    fi
    
    log_success "Dependencies installed successfully"
}

# Function to install dependencies on Arch Linux
install_arch_deps() {
    log_info "Installing dependencies for Arch Linux..."
    
    sudo pacman -S --needed wget xz parted dosfstools e2fsprogs rsync tar util-linux pigz
    
    log_success "Dependencies installed successfully"
}

# Function to check and install dependencies
install_dependencies() {
    local os=$(detect_os)
    
    log_info "Detected OS: $os"
    
    case "$os" in
        "debian")
            install_debian_deps
            ;;
        "redhat")
            install_redhat_deps
            ;;
        "arch")
            install_arch_deps
            ;;
        "macos")
            install_macos_deps
            ;;
        "windows")
            log_warning "Windows detected. Please use WSL (Windows Subsystem for Linux)"
            log_info "Install WSL with Ubuntu and run this script from within WSL"
            exit 1
            ;;
        *)
            log_error "Unsupported operating system: $os"
            log_info "Please install the following packages manually:"
            log_info "  wget, xz-utils, parted, dosfstools, e2fsprogs, rsync, tar, coreutils"
            exit 1
            ;;
    esac
}

# Function to set up project permissions
setup_permissions() {
    log_info "Setting up file permissions..."
    
    # Make all scripts executable
    chmod +x scripts/*.sh
    chmod +x recovery/*.sh
    chmod +x recovery/recovery-mode
    chmod +x configs/*.sh
    
    log_success "File permissions set up successfully"
}

# Function to create necessary directories
setup_directories() {
    log_info "Creating project directories..."
    
    # Create directories if they don't exist
    mkdir -p images
    mkdir -p logs
    
    log_success "Project directories created"
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in wget xz tar parted mkfs.fat mkfs.ext4 rsync; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All required tools are available"
        return 0
    else
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
}

# Function to show next steps
show_next_steps() {
    log_success "Setup completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Download a Raspberry Pi Ubuntu image:"
    echo "   ./scripts/download-image.sh"
    echo
    echo "2. Create a boot disk (replace /dev/sdX with your device):"
    echo "   sudo ./scripts/create-boot-disk.sh /dev/sdX"
    echo
    echo "3. Insert the SD card into your Raspberry Pi and boot"
    echo
    log_info "For detailed usage instructions, see README.md"
    echo
    log_warning "Always verify your target device before creating boot disks!"
    log_warning "The create-boot-disk.sh script will erase all data on the target device!"
}

# Function to show usage
show_usage() {
    cat << EOF
Setup Script for Raspberry Pi Boot Disk Project

Usage: $0 [OPTIONS]

OPTIONS:
    -y, --yes       Skip confirmation prompts
    -h, --help      Show this help message

EXAMPLES:
    $0              # Interactive setup
    $0 -y           # Automatic setup

EOF
}

# Main function
main() {
    local skip_confirm="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                skip_confirm="true"
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
    
    log_info "Raspberry Pi Boot Disk Project Setup"
    echo
    
    # Confirm setup
    if [ "$skip_confirm" != "true" ]; then
        echo "This script will:"
        echo "- Install required system dependencies"
        echo "- Set up file permissions"
        echo "- Create project directories"
        echo
        read -p "Continue with setup? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled"
            exit 0
        fi
    fi
    
    # Run setup steps
    install_dependencies
    setup_permissions
    setup_directories
    
    # Verify installation
    if verify_installation; then
        show_next_steps
    else
        log_error "Setup verification failed"
        log_info "Please check the error messages above and install missing dependencies"
        exit 1
    fi
}

# Run main function
main "$@"