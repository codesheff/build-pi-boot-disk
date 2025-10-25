#!/bin/bash

# Recovery System Management Script
# Provides tools for managing the recovery system

set -e

# Configuration
RECOVERY_CONF="/mnt/recovery/recovery.conf"
BACKUP_DIR="/mnt/recovery/backup"
LOG_DIR="/mnt/recovery/logs"
SCRIPTS_DIR="/mnt/recovery/scripts"

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
Recovery System Management Tool

Usage: $0 COMMAND [OPTIONS]

COMMANDS:
    status              Show recovery system status
    backup              Create a backup of main system
    restore             Restore main system from backup
    list                List available backups
    clean               Clean old backups
    logs                Show recent logs
    info                Show system information
    help                Show this help message

BACKUP OPTIONS:
    -n, --name NAME     Backup name
    -f, --full          Full backup (default: incremental)
    -c, --compress N    Compression level 1-9

RESTORE OPTIONS:
    -b, --backup FILE   Specific backup to restore
    -f, --force         Force without confirmation

EXAMPLES:
    $0 status                           # Show system status
    $0 backup -n "before-update"        # Named backup
    $0 restore -b system_backup.tar.gz  # Restore specific backup
    $0 list                             # List backups
    $0 clean                            # Clean old backups

EOF
}

# Function to load configuration
load_config() {
    if [ -f "$RECOVERY_CONF" ]; then
        source "$RECOVERY_CONF"
    else
        log_error "Recovery configuration not found"
        return 1
    fi
}

# Function to show status
show_status() {
    log_info "Recovery System Status"
    echo
    
    if load_config; then
        echo "System Name: $SYSTEM_NAME"
        echo "Device: $DEVICE"
        echo "Created: $CREATED_DATE"
        echo "Last Backup: $BACKUP_DATE"
        echo
    fi
    
    # Check if we're in recovery mode
    if mount | grep -q "/mnt/recovery"; then
        log_success "Currently in RECOVERY MODE"
        echo "Main partition: $(mount | grep "$MAIN_PARTITION" | cut -d' ' -f3 || echo "Not mounted")"
    else
        log_info "Currently in NORMAL MODE"
        
        # Check recovery trigger
        if [ -f "/boot/recovery_mode" ]; then
            log_warning "Recovery mode ENABLED for next boot"
        else
            log_info "Recovery mode disabled"
        fi
    fi
    
    echo
    
    # Show partition information
    log_info "Partition Information:"
    if load_config; then
        df -h "$MAIN_PARTITION" "$RECOVERY_PARTITION" 2>/dev/null || true
    fi
    
    echo
    
    # Show backup information
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
        local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "Backups: $backup_count files, $backup_size total"
    else
        echo "Backups: Not available"
    fi
}

# Function to list backups
list_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "Backup directory not found"
        return
    fi
    
    log_info "Available Backups:"
    echo
    
    if [ "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
        printf "%-40s %-15s %-20s\n" "Backup Name" "Size" "Date"
        printf "%-40s %-15s %-20s\n" "$(printf '%*s' 40 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 20 | tr ' ' '-')"
        
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p %s\n' | sort -rn | while read timestamp path size; do
            local name=$(basename "$path")
            local date_str=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M')
            local size_human=$(numfmt --to=iec --suffix=B $size)
            printf "%-40s %-15s %-20s\n" "$name" "$size_human" "$date_str"
            
            # Show backup info if available
            if [ -f "${path}.info" ]; then
                local backup_type=$(grep "Type:" "${path}.info" | cut -d' ' -f2-)
                printf "  └─ Type: %s\n" "$backup_type"
            fi
        done
    else
        echo "No backups found"
    fi
    echo
}

# Function to show logs
show_logs() {
    local log_type="$1"
    
    if [ ! -d "$LOG_DIR" ]; then
        log_warning "Log directory not found"
        return
    fi
    
    case "$log_type" in
        backup)
            if [ -f "$LOG_DIR/backup_history.log" ]; then
                log_info "Recent Backup History:"
                tail -10 "$LOG_DIR/backup_history.log"
            else
                log_warning "No backup history found"
            fi
            ;;
        restore)
            if [ -f "$LOG_DIR/restore_history.log" ]; then
                log_info "Recent Restore History:"
                tail -10 "$LOG_DIR/restore_history.log"
            else
                log_warning "No restore history found"
            fi
            ;;
        *)
            log_info "Available log files:"
            find "$LOG_DIR" -name "*.log" -type f -printf '%T+ %p\n' | sort -r | head -10 | while read date file; do
                echo "  $(basename "$file") - $(echo "$date" | cut -d+ -f1)"
            done
            ;;
    esac
}

# Function to clean old backups
clean_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warning "Backup directory not found"
        return
    fi
    
    local keep_count=5
    
    log_info "Cleaning old backups (keeping last $keep_count)..."
    
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" | wc -l)
    
    if [ "$backup_count" -le "$keep_count" ]; then
        log_info "No cleanup needed ($backup_count backups found)"
        return
    fi
    
    local to_delete=$((backup_count - keep_count))
    log_info "Will delete $to_delete old backup(s)"
    
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | head -$to_delete | cut -d' ' -f2- | while read backup_file; do
        log_info "Removing: $(basename "$backup_file")"
        rm -f "$backup_file" "${backup_file}.info"
    done
    
    log_success "Cleanup completed"
}

# Function to show system information
show_info() {
    log_info "System Information"
    echo
    
    # Basic system info
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p)"
    echo
    
    # Memory info
    echo "Memory Usage:"
    free -h
    echo
    
    # Disk usage
    echo "Disk Usage:"
    df -h | grep -E "(Filesystem|/dev/)"
    echo
    
    # Recovery system info
    if load_config; then
        echo "Recovery Configuration:"
        echo "  System Name: $SYSTEM_NAME"
        echo "  Device: $DEVICE"
        echo "  Main Partition: $MAIN_PARTITION"
        echo "  Recovery Partition: $RECOVERY_PARTITION"
        echo "  EFI Partition: $EFI_PARTITION"
    fi
}

# Main function
main() {
    local command="$1"
    shift || true
    
    case "$command" in
        status)
            show_status
            ;;
        backup)
            if [ -x "$SCRIPTS_DIR/backup.sh" ]; then
                "$SCRIPTS_DIR/backup.sh" "$@"
            else
                log_error "Backup script not found or not executable"
            fi
            ;;
        restore)
            if [ -x "$SCRIPTS_DIR/restore.sh" ]; then
                "$SCRIPTS_DIR/restore.sh" "$@"
            else
                log_error "Restore script not found or not executable"
            fi
            ;;
        list)
            list_backups
            ;;
        clean)
            clean_backups
            ;;
        logs)
            show_logs "$1"
            ;;
        info)
            show_info
            ;;
        help|--help|-h)
            show_usage
            ;;
        "")
            log_error "No command specified"
            show_usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Check if we're in recovery mode for commands that require it
case "$1" in
    backup|restore)
        if ! mount | grep -q "/mnt/recovery"; then
            log_error "This command must be run from recovery mode"
            log_info "To enter recovery mode:"
            log_info "1. Boot into main system"
            log_info "2. Run: sudo recovery-mode enable"
            log_info "3. Reboot: sudo reboot"
            exit 1
        fi
        ;;
esac

# Run main function
main "$@"