#!/bin/bash

# System Customization Extractor
# Extracts user settings, network config, and customizations from current system
# Usage: ./extract_customizations.sh [output_directory]

set -e

# Configuration
DEFAULT_OUTPUT_DIR="/home/pi/system-customizations"

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

# Function to create output directory
create_output_directory() {
    local output_dir="$1"
    
    if [[ ! -d "$output_dir" ]]; then
        print_status "Creating output directory: $output_dir"
        mkdir -p "$output_dir" || {
            print_error "Failed to create output directory: $output_dir"
            exit 1
        }
    fi
}

# Function to extract user accounts
extract_users() {
    local output_dir="$1"
    
    print_status "Extracting user account information..."
    
    # Extract non-system users (UID >= 1000)
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $0}' /etc/passwd > "$output_dir/users.txt"
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $0}' /etc/shadow > "$output_dir/shadow.txt" 2>/dev/null || {
        print_warning "Could not extract shadow file (requires root)"
        touch "$output_dir/shadow.txt"
    }
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $0}' /etc/group > "$output_dir/groups.txt"
    
    # Extract user directories and settings
    local users_found=0
    while IFS=: read -r username _ uid gid _ home shell; do
        if [[ $uid -ge 1000 && "$username" != "nobody" ]]; then
            users_found=$((users_found + 1))
            print_status "Found user: $username (UID: $uid, Home: $home)"
            
            # Create user-specific directory
            local user_dir="$output_dir/users/$username"
            mkdir -p "$user_dir"
            
            # Save user info
            echo "username=$username" > "$user_dir/info.txt"
            echo "uid=$uid" >> "$user_dir/info.txt"
            echo "gid=$gid" >> "$user_dir/info.txt"
            echo "home=$home" >> "$user_dir/info.txt"
            echo "shell=$shell" >> "$user_dir/info.txt"
            
            # Extract SSH keys if they exist
            if [[ -d "$home/.ssh" ]]; then
                print_status "Backing up SSH keys for $username"
                cp -r "$home/.ssh" "$user_dir/" 2>/dev/null || print_warning "Could not backup SSH keys for $username"
            fi
            
            # Extract bash configuration
            for file in .bashrc .bash_profile .profile .bash_aliases; do
                if [[ -f "$home/$file" ]]; then
                    cp "$home/$file" "$user_dir/" 2>/dev/null || true
                fi
            done
            
            # Extract sudo permissions
            sudo -l -U "$username" > "$user_dir/sudo_permissions.txt" 2>/dev/null || echo "No sudo permissions" > "$user_dir/sudo_permissions.txt"
        fi
    done < /etc/passwd
    
    print_success "Extracted $users_found user accounts"
}

# Function to extract network configuration
extract_network_config() {
    local output_dir="$1"
    
    print_status "Extracting network configuration..."
    
    local network_dir="$output_dir/network"
    mkdir -p "$network_dir"
    
    # Netplan configuration (Ubuntu's default)
    if [[ -d /etc/netplan ]]; then
        print_status "Backing up Netplan configuration"
        cp -r /etc/netplan "$network_dir/" 2>/dev/null || print_warning "Could not backup Netplan config"
    fi
    
    # Network interfaces (fallback)
    if [[ -f /etc/network/interfaces ]]; then
        cp /etc/network/interfaces "$network_dir/" 2>/dev/null || true
    fi
    
    # Hostname and hosts
    cp /etc/hostname "$network_dir/" 2>/dev/null || true
    cp /etc/hosts "$network_dir/" 2>/dev/null || true
    
    # DNS configuration
    cp /etc/resolv.conf "$network_dir/" 2>/dev/null || true
    if [[ -f /etc/systemd/resolved.conf ]]; then
        cp /etc/systemd/resolved.conf "$network_dir/" 2>/dev/null || true
    fi
    
    # WiFi configuration
    if [[ -d /etc/wpa_supplicant ]]; then
        print_status "Backing up WiFi configuration"
        cp -r /etc/wpa_supplicant "$network_dir/" 2>/dev/null || print_warning "Could not backup WiFi config"
    fi
    
    print_success "Network configuration extracted"
}

# Function to extract system settings
extract_system_settings() {
    local output_dir="$1"
    
    print_status "Extracting system settings..."
    
    local system_dir="$output_dir/system"
    mkdir -p "$system_dir"
    
    # Timezone
    cp /etc/timezone "$system_dir/" 2>/dev/null || true
    if [[ -L /etc/localtime ]]; then
        readlink /etc/localtime > "$system_dir/localtime_link.txt"
    fi
    
    # Locale settings
    if [[ -f /etc/locale.gen ]]; then
        cp /etc/locale.gen "$system_dir/" 2>/dev/null || true
    fi
    if [[ -f /etc/default/locale ]]; then
        cp /etc/default/locale "$system_dir/" 2>/dev/null || true
    fi
    
    # Keyboard layout
    if [[ -f /etc/default/keyboard ]]; then
        cp /etc/default/keyboard "$system_dir/" 2>/dev/null || true
    fi
    
    # Package lists
    print_status "Extracting installed packages list"
    dpkg --get-selections > "$system_dir/packages.txt" 2>/dev/null || true
    apt list --installed > "$system_dir/apt_packages.txt" 2>/dev/null || true
    
    # Service status
    systemctl list-unit-files --type=service --state=enabled > "$system_dir/enabled_services.txt" 2>/dev/null || true
    
    print_success "System settings extracted"
}

# Function to extract SSH configuration
extract_ssh_config() {
    local output_dir="$1"
    
    print_status "Extracting SSH configuration..."
    
    local ssh_dir="$output_dir/ssh"
    mkdir -p "$ssh_dir"
    
    # SSH daemon configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        cp /etc/ssh/sshd_config "$ssh_dir/" 2>/dev/null || true
    fi
    
    # SSH client configuration
    if [[ -f /etc/ssh/ssh_config ]]; then
        cp /etc/ssh/ssh_config "$ssh_dir/" 2>/dev/null || true
    fi
    
    # SSH host keys (for server identity)
    if [[ -d /etc/ssh ]]; then
        cp /etc/ssh/ssh_host_* "$ssh_dir/" 2>/dev/null || print_warning "Could not backup SSH host keys"
    fi
    
    print_success "SSH configuration extracted"
}

# Function to extract custom software and configurations
extract_custom_software() {
    local output_dir="$1"
    
    print_status "Extracting custom software configurations..."
    
    local custom_dir="$output_dir/custom"
    mkdir -p "$custom_dir"
    
    # Cron jobs
    print_status "Backing up cron jobs"
    crontab -l > "$custom_dir/user_crontab.txt" 2>/dev/null || echo "No user crontab" > "$custom_dir/user_crontab.txt"
    if [[ -d /etc/cron.d ]]; then
        cp -r /etc/cron.d "$custom_dir/" 2>/dev/null || true
    fi
    
    # Custom scripts in common locations
    for dir in /usr/local/bin /usr/local/sbin /home/*/bin; do
        if [[ -d "$dir" ]] && [[ $(ls -A "$dir" 2>/dev/null) ]]; then
            local dirname=$(basename "$dir")
            local parent=$(dirname "$dir")
            mkdir -p "$custom_dir/scripts/$(basename "$parent")"
            cp -r "$dir" "$custom_dir/scripts/$(basename "$parent")/" 2>/dev/null || true
        fi
    done
    
    # Docker configuration (if present)
    if command -v docker &>/dev/null; then
        print_status "Found Docker, backing up configuration"
        mkdir -p "$custom_dir/docker"
        docker --version > "$custom_dir/docker/version.txt" 2>/dev/null || true
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > "$custom_dir/docker/containers.txt" 2>/dev/null || true
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" > "$custom_dir/docker/images.txt" 2>/dev/null || true
    fi
    
    # Snap packages (if present)
    if command -v snap &>/dev/null; then
        print_status "Found Snap, listing installed packages"
        snap list > "$custom_dir/snap_packages.txt" 2>/dev/null || true
    fi
    
    print_success "Custom software configurations extracted"
}

# Function to create restoration script
create_restoration_script() {
    local output_dir="$1"
    
    print_status "Creating restoration script..."
    
    cat > "$output_dir/restore_customizations.sh" << 'EOF'
#!/bin/bash

# Customization Restoration Script
# Restores user settings and configurations to a fresh Ubuntu installation
# Usage: ./restore_customizations.sh [customization_directory]

set -e

CUSTOM_DIR="${1:-$(dirname "$0")}"

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

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

print_status "Restoring customizations from: $CUSTOM_DIR"

# Restore users
if [[ -d "$CUSTOM_DIR/users" ]]; then
    print_status "Restoring user accounts..."
    for user_dir in "$CUSTOM_DIR/users"/*; do
        if [[ -d "$user_dir" ]]; then
            username=$(basename "$user_dir")
            print_status "Restoring user: $username"
            
            # Create user if it doesn't exist
            if ! id "$username" &>/dev/null; then
                if [[ -f "$user_dir/info.txt" ]]; then
                    source "$user_dir/info.txt"
                    useradd -m -u "$uid" -g "$gid" -d "$home" -s "$shell" "$username" 2>/dev/null || true
                fi
            fi
            
            # Restore SSH keys
            if [[ -d "$user_dir/.ssh" ]]; then
                cp -r "$user_dir/.ssh" "$home/" 2>/dev/null || true
                chown -R "$username:$username" "$home/.ssh" 2>/dev/null || true
                chmod 700 "$home/.ssh" 2>/dev/null || true
                chmod 600 "$home/.ssh"/* 2>/dev/null || true
            fi
            
            # Restore bash configuration
            for file in .bashrc .bash_profile .profile .bash_aliases; do
                if [[ -f "$user_dir/$file" ]]; then
                    cp "$user_dir/$file" "$home/" 2>/dev/null || true
                    chown "$username:$username" "$home/$file" 2>/dev/null || true
                fi
            done
        fi
    done
fi

# Restore network configuration
if [[ -d "$CUSTOM_DIR/network" ]]; then
    print_status "Restoring network configuration..."
    
    if [[ -d "$CUSTOM_DIR/network/netplan" ]]; then
        cp -r "$CUSTOM_DIR/network/netplan"/* /etc/netplan/ 2>/dev/null || true
    fi
    
    if [[ -f "$CUSTOM_DIR/network/hostname" ]]; then
        cp "$CUSTOM_DIR/network/hostname" /etc/ 2>/dev/null || true
    fi
    
    if [[ -f "$CUSTOM_DIR/network/hosts" ]]; then
        cp "$CUSTOM_DIR/network/hosts" /etc/ 2>/dev/null || true
    fi
fi

# Restore system settings
if [[ -d "$CUSTOM_DIR/system" ]]; then
    print_status "Restoring system settings..."
    
    if [[ -f "$CUSTOM_DIR/system/timezone" ]]; then
        cp "$CUSTOM_DIR/system/timezone" /etc/ 2>/dev/null || true
        dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
    fi
    
    if [[ -f "$CUSTOM_DIR/system/locale.gen" ]]; then
        cp "$CUSTOM_DIR/system/locale.gen" /etc/ 2>/dev/null || true
        locale-gen 2>/dev/null || true
    fi
    
    if [[ -f "$CUSTOM_DIR/system/keyboard" ]]; then
        cp "$CUSTOM_DIR/system/keyboard" /etc/default/ 2>/dev/null || true
    fi
fi

# Restore SSH configuration
if [[ -d "$CUSTOM_DIR/ssh" ]]; then
    print_status "Restoring SSH configuration..."
    
    if [[ -f "$CUSTOM_DIR/ssh/sshd_config" ]]; then
        cp "$CUSTOM_DIR/ssh/sshd_config" /etc/ssh/ 2>/dev/null || true
    fi
    
    # Restore SSH host keys (preserve server identity)
    for key_file in "$CUSTOM_DIR/ssh"/ssh_host_*; do
        if [[ -f "$key_file" ]]; then
            cp "$key_file" /etc/ssh/ 2>/dev/null || true
            chmod 600 "/etc/ssh/$(basename "$key_file")" 2>/dev/null || true
        fi
    done
    
    systemctl restart ssh 2>/dev/null || true
fi

print_success "Customization restoration completed!"
print_status "You may need to:"
print_status "  1. Reboot the system to apply all changes"
print_status "  2. Manually verify network connectivity"
print_status "  3. Check that all services are running correctly"

EOF

    chmod +x "$output_dir/restore_customizations.sh"
    print_success "Restoration script created: $output_dir/restore_customizations.sh"
}

# Function to create summary
create_summary() {
    local output_dir="$1"
    
    print_status "Creating extraction summary..."
    
    cat > "$output_dir/EXTRACTION_SUMMARY.txt" << EOF
System Customization Extraction Summary
======================================

Extraction Date: $(date)
Source System: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)
Architecture: $(uname -m)

Extracted Components:
--------------------

Users:
$(ls "$output_dir/users" 2>/dev/null | sed 's/^/  - /' || echo "  - None")

Network Configuration:
  - Netplan configuration: $([ -d "$output_dir/network/netplan" ] && echo "Yes" || echo "No")
  - WiFi configuration: $([ -d "$output_dir/network/wpa_supplicant" ] && echo "Yes" || echo "No")
  - Hostname and hosts: $([ -f "$output_dir/network/hostname" ] && echo "Yes" || echo "No")

System Settings:
  - Timezone: $([ -f "$output_dir/system/timezone" ] && cat "$output_dir/system/timezone" || echo "Not extracted")
  - Installed packages: $([ -f "$output_dir/system/packages.txt" ] && wc -l < "$output_dir/system/packages.txt" || echo "0") packages

SSH Configuration:
  - SSH daemon config: $([ -f "$output_dir/ssh/sshd_config" ] && echo "Yes" || echo "No")
  - SSH host keys: $(ls "$output_dir/ssh"/ssh_host_* 2>/dev/null | wc -l || echo "0") keys

Custom Software:
  - Docker: $(command -v docker &>/dev/null && echo "Detected" || echo "Not found")
  - Snap packages: $([ -f "$output_dir/custom/snap_packages.txt" ] && echo "Listed" || echo "None")

Files and Directories:
$(find "$output_dir" -type f | wc -l) files extracted
$(du -sh "$output_dir" | cut -f1) total size

Usage:
------
1. Use restore_customizations.sh to apply these settings to a fresh Ubuntu installation
2. Run the restoration script as root on the target system
3. Reboot after restoration to ensure all changes take effect

EOF

    print_success "Summary created: $output_dir/EXTRACTION_SUMMARY.txt"
}

# Main function
main() {
    local output_dir="${1:-$DEFAULT_OUTPUT_DIR}"
    
    print_status "System Customization Extractor Starting..."
    print_status "Output directory: $output_dir"
    
    # Create output directory
    create_output_directory "$output_dir"
    
    # Extract all components
    extract_users "$output_dir"
    extract_network_config "$output_dir"
    extract_system_settings "$output_dir"
    extract_ssh_config "$output_dir"
    extract_custom_software "$output_dir"
    
    # Create restoration script and summary
    create_restoration_script "$output_dir"
    create_summary "$output_dir"
    
    print_success "Customization extraction completed!"
    print_status "Extracted to: $output_dir"
    print_status "Use restore_customizations.sh to apply to fresh Ubuntu installations"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OUTPUT_DIRECTORY]"
    echo ""
    echo "Arguments:"
    echo "  OUTPUT_DIRECTORY  Directory to store extracted settings (default: $DEFAULT_OUTPUT_DIR)"
    echo ""
    echo "This script extracts:"
    echo "  - User accounts and SSH keys"
    echo "  - Network configuration (Netplan, WiFi)"
    echo "  - System settings (timezone, locale, packages)"
    echo "  - SSH configuration and host keys"
    echo "  - Custom software and scripts"
    echo ""
    echo "Examples:"
    echo "  $0                    # Extract to default directory"
    echo "  $0 /tmp/my-settings   # Extract to custom directory"
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"