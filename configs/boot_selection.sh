#!/bin/bash
# Boot Selection Script for Raspberry Pi Recovery System
# This script determines which system to boot based on recovery mode trigger

# Configuration files
RECOVERY_TRIGGER="/boot/recovery_mode"
CMDLINE_FILE="/boot/cmdline.txt" 
BOOT_SELECTION_FILE="/boot/boot_selection.txt"

# Default boot parameters
DEFAULT_BOOT="console=serial0,115200 console=tty1 root=LABEL=pi-system-main rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet splash"
RECOVERY_BOOT="console=serial0,115200 console=tty1 root=LABEL=pi-system-recovery rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait"

# Log function
log_boot() {
    echo "[$(date)] BOOT: $1" >> /boot/boot.log
}

# Check if recovery mode is triggered
if [ -f "$RECOVERY_TRIGGER" ]; then
    # Recovery mode
    log_boot "Recovery mode triggered - booting into recovery system"
    echo "$RECOVERY_BOOT" > "$CMDLINE_FILE"
    
    # Create boot selection indicator
    cat > "$BOOT_SELECTION_FILE" << EOF
# Boot Selection Status
boot_mode=recovery
boot_time=$(date)
boot_reason=recovery_triggered
EOF
    
    # Remove the trigger file to prevent boot loop
    rm -f "$RECOVERY_TRIGGER"
    
else
    # Normal mode
    log_boot "Normal boot mode - booting into main system"
    echo "$DEFAULT_BOOT" > "$CMDLINE_FILE"
    
    # Create boot selection indicator
    cat > "$BOOT_SELECTION_FILE" << EOF
# Boot Selection Status  
boot_mode=normal
boot_time=$(date)
boot_reason=normal_boot
EOF
fi

# Set appropriate root filesystem
CURRENT_MODE=$(grep "boot_mode=" "$BOOT_SELECTION_FILE" | cut -d'=' -f2)

if [ "$CURRENT_MODE" = "recovery" ]; then
    # Mount recovery partition as root
    log_boot "Configuring recovery boot parameters"
    
    # Additional recovery-specific settings can go here
    # For example, mounting the main partition for backup/restore operations
    
else
    # Mount main partition as root  
    log_boot "Configuring normal boot parameters"
    
    # Additional normal boot settings can go here
fi

log_boot "Boot selection completed - mode: $CURRENT_MODE"

exit 0