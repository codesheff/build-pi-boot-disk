#!/bin/bash

# Recovery System Restore Script
# Restores the main system from backup

set -e

# Configuration
RECOVERY_CONF="/mnt/recovery/recovery.conf"
BACKUP_DIR="/mnt/recovery/backup"
LOG_DIR="/mnt/recovery/logs"
LOG_FILE="$LOG_DIR/restore_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${GREEN}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restores the main system from backup

OPTIONS:
    -b, --backup FILE       Specific backup file to restore (default: latest)
    -f, --force             Force restore without confirmation
    -v, --verbose           Verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0                              # Restore from latest backup
    $0 -b system_backup.tar.gz      # Restore from specific backup
    $0 -f                           # Force restore without confirmation

EOF
}

# Function to load recovery configuration
load_config() {
    if [ ! -f "$RECOVERY_CONF" ]; then
        log_error "Recovery configuration not found: $RECOVERY_CONF"
        exit 1
    fi
    
    source "$RECOVERY_CONF"
    
    log_info "Recovery configuration loaded"
    log_info "System name: $SYSTEM_NAME"
    log_info "Device: $DEVICE"
    log_info "Main partition: $MAIN_PARTITION"
}

# Function to find backup file
find_backup() {
    local specified_backup="$1"
    
    if [ -n "$specified_backup" ]; then
        local backup_path="$BACKUP_DIR/$specified_backup"
        if [ ! -f "$backup_path" ]; then
            log_error "Specified backup file not found: $backup_path"
            exit 1
        fi
        echo "$backup_path"
        return
    fi
    
    # Find latest backup
    local latest_backup=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup files found in $BACKUP_DIR"
        exit 1
    fi
    
    log_info "Latest backup found: $(basename "$latest_backup")"
    echo "$latest_backup"
}

# Function to verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    log_info "Verifying backup integrity..."
    
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_error "Backup file is corrupted or not a valid tar.gz file"
        exit 1
    fi
    
    log_success "Backup integrity verified"
}

# Function to confirm restore operation
confirm_restore() {
    local backup_file="$1"
    local force="$2"
    
    if [ "$force" = "true" ]; then
        return
    fi
    
    log_warning "WARNING: This will completely replace the main system!"
    log_warning "All current data on the main partition will be lost!"
    log_info "Backup to restore: $(basename "$backup_file")"
    echo
    read -p "Type 'RESTORE' to continue: " confirmation
    
    if [ "$confirmation" != "RESTORE" ]; then
        log_info "Restore operation cancelled"
        exit 0
    fi
}

# Function to mount partitions
mount_partitions() {
    log_info "Mounting partitions..."
    
    # Create mount points
    mkdir -p /mnt/main_restore
    
    # Mount main partition
    if ! mount "$MAIN_PARTITION" /mnt/main_restore; then
        log_error "Failed to mount main partition: $MAIN_PARTITION"
        exit 1
    fi
    
    log_success "Partitions mounted successfully"
}

# Function to backup current system
backup_current() {
    log_info "Creating backup of current system before restore..."
    
    local current_backup="$BACKUP_DIR/pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    # Create backup of essential files only (faster)
    tar -czf "$current_backup" \
        -C /mnt/main_restore \
        --exclude="proc/*" \
        --exclude="sys/*" \
        --exclude="dev/*" \
        --exclude="tmp/*" \
        --exclude="var/cache/*" \
        --exclude="var/log/*" \
        --exclude="mnt/*" \
        --exclude="media/*" \
        etc home root var/lib 2>/dev/null || true
    
    log_success "Current system backup created: $(basename "$current_backup")"
}

# Function to restore system
restore_system() {
    local backup_file="$1"
    
    log_info "Starting system restore..."
    log_info "Source: $(basename "$backup_file")"
    log_info "Target: $MAIN_PARTITION"
    
    # Clear the main partition (except mount point)
    log_info "Clearing main partition..."
    find /mnt/main_restore -mindepth 1 -maxdepth 1 ! -name "lost+found" -exec rm -rf {} \; 2>/dev/null || true
    
    # Extract backup
    log_info "Extracting backup (this may take several minutes)..."
    if ! tar -xzf "$backup_file" -C /mnt/main_restore; then
        log_error "Failed to extract backup"
        exit 1
    fi
    
    # Restore special directories
    log_info "Restoring special directories..."
    mkdir -p /mnt/main_restore/{proc,sys,dev,tmp}
    chmod 1777 /mnt/main_restore/tmp
    
    # Update fstab if needed
    if [ -f "/mnt/main_restore/etc/fstab" ]; then
        # Ensure recovery partition entry exists
        if ! grep -q "/mnt/recovery" /mnt/main_restore/etc/fstab; then
            echo "" >> /mnt/main_restore/etc/fstab
            echo "# Recovery partition" >> /mnt/main_restore/etc/fstab
            echo "$RECOVERY_PARTITION /mnt/recovery ext4 defaults,noauto 0 2" >> /mnt/main_restore/etc/fstab
        fi
    fi
    
    # Ensure recovery-mode script exists
    if [ ! -f "/mnt/main_restore/usr/local/bin/recovery-mode" ]; then
        log_info "Installing recovery-mode script..."
        mkdir -p /mnt/main_restore/usr/local/bin
        cp /mnt/recovery/scripts/recovery-mode /mnt/main_restore/usr/local/bin/
        chmod +x /mnt/main_restore/usr/local/bin/recovery-mode
    fi
    
    log_success "System restore completed successfully"
}

# Function to cleanup
cleanup_restore() {
    log_info "Cleaning up..."
    
    # Unmount partitions
    umount /mnt/main_restore 2>/dev/null || true
    rmdir /mnt/main_restore 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Function to update restore log
update_restore_log() {
    local backup_file="$1"
    
    cat >> "$LOG_DIR/restore_history.log" << EOF
$(date '+%Y-%m-%d %H:%M:%S'): Restored from $(basename "$backup_file")
EOF
}

# Main function
main() {
    local backup_file=""
    local force="false"
    local verbose="false"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--backup)
                backup_file="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                set -x
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
    
    log_info "Starting recovery system restore"
    
    # Load configuration
    load_config
    
    # Find backup file
    backup_file=$(find_backup "$backup_file")
    
    # Verify backup
    verify_backup "$backup_file"
    
    # Confirm operation
    confirm_restore "$backup_file" "$force"
    
    # Mount partitions
    mount_partitions
    
    # Backup current system
    backup_current
    
    # Restore system
    restore_system "$backup_file"
    
    # Update logs
    update_restore_log "$backup_file"
    
    # Cleanup
    cleanup_restore
    
    log_success "System restore completed successfully!"
    echo
    log_info "The system has been restored from: $(basename "$backup_file")"
    log_info "Reboot to start the restored system: sudo reboot"
    echo
    log_info "Log file: $LOG_FILE"
}

# Set up cleanup on exit
trap cleanup_restore EXIT

# Check if we're in recovery mode
if ! mount | grep -q "/mnt/recovery"; then
    log_error "This script must be run from recovery mode"
    log_info "To enter recovery mode:"
    log_info "1. Boot into main system"
    log_info "2. Run: sudo recovery-mode enable"
    log_info "3. Reboot: sudo reboot"
    exit 1
fi

# Check dependencies
for cmd in tar find; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
done

# Run main function
main "$@"