#!/bin/bash

# Recovery System Backup Script
# Creates backups of the main system

set -e

# Configuration
RECOVERY_CONF="/mnt/recovery/recovery.conf"
BACKUP_DIR="/mnt/recovery/backup"
LOG_DIR="/mnt/recovery/logs"
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

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

Creates a backup of the main system

OPTIONS:
    -n, --name NAME         Backup name (default: auto-generated)
    -f, --full              Create full backup (default: incremental)
    -c, --compress LEVEL    Compression level 1-9 (default: 6)
    -v, --verbose           Verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0                              # Create incremental backup
    $0 -n "before-update"           # Named backup
    $0 -f                           # Full backup
    $0 -c 9                         # Maximum compression

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
    log_info "Main partition: $MAIN_PARTITION"
}

# Function to check available space
check_space() {
    log_info "Checking available space..."
    
    local recovery_free=$(df -BG /mnt/recovery | awk 'NR==2 {print $4}' | sed 's/G//')
    local main_used=$(df -BG "$MAIN_PARTITION" | awk 'NR==2 {print $3}' | sed 's/G//')
    
    log_info "Recovery partition free space: ${recovery_free}GB"
    log_info "Main partition used space: ${main_used}GB"
    
    # Check if we have enough space (with 20% buffer)
    local required_space=$((main_used * 120 / 100))
    
    if [ "$recovery_free" -lt "$required_space" ]; then
        log_warning "Low disk space on recovery partition"
        log_warning "Required: ${required_space}GB, Available: ${recovery_free}GB"
        log_info "Consider cleaning old backups or using higher compression"
    else
        log_success "Sufficient space available"
    fi
}

# Function to mount main partition
mount_main_partition() {
    log_info "Mounting main partition..."
    
    # Create mount point
    mkdir -p /mnt/main_backup
    
    # Mount main partition
    if ! mount "$MAIN_PARTITION" /mnt/main_backup; then
        log_error "Failed to mount main partition: $MAIN_PARTITION"
        exit 1
    fi
    
    log_success "Main partition mounted successfully"
}

# Function to cleanup old backups
cleanup_old_backups() {
    local keep_count=5  # Keep last 5 backups
    
    log_info "Cleaning up old backups (keeping last $keep_count)..."
    
    # Find and remove old backups
    local old_backups=$(find "$BACKUP_DIR" -name "system_backup_*.tar.gz" -type f -printf '%T@ %p\n' | sort -rn | tail -n +$((keep_count + 1)) | cut -d' ' -f2-)
    
    if [ -n "$old_backups" ]; then
        echo "$old_backups" | while read backup_file; do
            log_info "Removing old backup: $(basename "$backup_file")"
            rm -f "$backup_file"
        done
        log_success "Old backups cleaned up"
    else
        log_info "No old backups to clean up"
    fi
}

# Function to create backup
create_backup() {
    local backup_name="$1"
    local backup_type="$2"
    local compression_level="$3"
    
    # Generate backup filename
    local timestamp=$(date +%Y%m%d_%H%M%S)
    if [ -n "$backup_name" ]; then
        local backup_file="$BACKUP_DIR/${backup_name}_${timestamp}.tar.gz"
    else
        local backup_file="$BACKUP_DIR/system_backup_${timestamp}.tar.gz"
    fi
    
    log_info "Creating $backup_type backup..."
    log_info "Target file: $(basename "$backup_file")"
    log_info "Compression level: $compression_level"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Determine tar options based on backup type
    local tar_options="-czf"
    
    if [ "$backup_type" = "incremental" ]; then
        # Find last full backup for incremental
        local last_backup=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        if [ -n "$last_backup" ]; then
            log_info "Base backup for incremental: $(basename "$last_backup")"
            # For simplicity, we'll create a full backup but could implement true incremental later
        fi
    fi
    
    # Create the backup with specific compression level
    log_info "Starting backup creation (this may take several minutes)..."
    
    # Use pigz for parallel compression if available, otherwise gzip
    if command -v pigz >/dev/null 2>&1; then
        export GZIP_PROG="pigz -$compression_level"
    else
        export GZIP_PROG="gzip -$compression_level"
    fi
    
    if tar --use-compress-program="$GZIP_PROG" \
           -cf "$backup_file" \
           -C /mnt/main_backup \
           --exclude="proc/*" \
           --exclude="sys/*" \
           --exclude="dev/*" \
           --exclude="tmp/*" \
           --exclude="var/cache/*" \
           --exclude="var/log/journal/*" \
           --exclude="var/tmp/*" \
           --exclude="mnt/*" \
           --exclude="media/*" \
           --exclude="lost+found" \
           --exclude="*.log" \
           --exclude="*.tmp" \
           --exclude=".cache/*" \
           . ; then
        
        log_success "Backup created successfully"
        
        # Get backup size
        local backup_size=$(du -h "$backup_file" | cut -f1)
        log_info "Backup size: $backup_size"
        
        # Create backup info file
        cat > "${backup_file}.info" << EOF
Backup Information
==================
Date: $(date)
Type: $backup_type
Compression: Level $compression_level
Size: $backup_size
System: $SYSTEM_NAME
Source: $MAIN_PARTITION
Log: $LOG_FILE
EOF
        
        # Update backup history
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Created $(basename "$backup_file") ($backup_size)" >> "$LOG_DIR/backup_history.log"
        
    else
        log_error "Failed to create backup"
        rm -f "$backup_file" "${backup_file}.info" 2>/dev/null || true
        exit 1
    fi
}

# Function to verify backup
verify_backup() {
    local backup_file="$1"
    
    log_info "Verifying backup integrity..."
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Backup verification passed"
    else
        log_error "Backup verification failed!"
        exit 1
    fi
}

# Function to cleanup
cleanup_backup() {
    log_info "Cleaning up..."
    
    # Unmount main partition
    umount /mnt/main_backup 2>/dev/null || true
    rmdir /mnt/main_backup 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Function to list existing backups
list_backups() {
    log_info "Existing backups:"
    echo
    
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        printf "%-30s %-15s %-20s\n" "Backup Name" "Size" "Date"
        printf "%-30s %-15s %-20s\n" "----------" "----" "----"
        
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p %s\n' | sort -rn | while read timestamp path size; do
            local name=$(basename "$path")
            local date_str=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M')
            local size_human=$(numfmt --to=iec --suffix=B $size)
            printf "%-30s %-15s %-20s\n" "$name" "$size_human" "$date_str"
        done
    else
        echo "No backups found"
    fi
    echo
}

# Main function
main() {
    local backup_name=""
    local backup_type="incremental"
    local compression_level=6
    local verbose="false"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                backup_name="$2"
                shift 2
                ;;
            -f|--full)
                backup_type="full"
                shift
                ;;
            -c|--compress)
                compression_level="$2"
                if [ "$compression_level" -lt 1 ] || [ "$compression_level" -gt 9 ]; then
                    log_error "Compression level must be between 1 and 9"
                    exit 1
                fi
                shift 2
                ;;
            -l|--list)
                list_backups
                exit 0
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
    
    log_info "Starting system backup"
    
    # Load configuration
    load_config
    
    # Check available space
    check_space
    
    # Mount main partition
    mount_main_partition
    
    # List existing backups
    list_backups
    
    # Create backup
    create_backup "$backup_name" "$backup_type" "$compression_level"
    
    # Verify backup
    local backup_file=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    verify_backup "$backup_file"
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Cleanup
    cleanup_backup
    
    log_success "System backup completed successfully!"
    echo
    log_info "Backup created: $(basename "$backup_file")"
    log_info "Log file: $LOG_FILE"
}

# Set up cleanup on exit
trap cleanup_backup EXIT

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
for cmd in tar find df; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
done

# Run main function
main "$@"