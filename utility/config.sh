#!/bin/bash

# Shared Configuration for Pi Disk Build Tools
# This file is sourced by multiple utility scripts to maintain consistent configuration

# Default directories
DEFAULT_DOWNLOAD_DIR="$HOME/ubuntu-images"

# Default Ubuntu settings
DEFAULT_VERSION="25.10"
DEFAULT_ARCH="arm64"

# Partition sizes (can be overridden by create_pi_disk.sh)
BOOT_PARTITION_SIZE="512M"
ROOT_PARTITION_SIZE="10240M"  # 10GB for each root partition
RECOVERY_PARTITION_SIZE="256M"  # 256MB for recovery OS

# Boot configuration
BOOT_MOUNT="/boot/firmware"  # Ubuntu 24.04+ boot mount point

# Colors for output (shared formatting)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Shared output functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
