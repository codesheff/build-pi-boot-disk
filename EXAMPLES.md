# Raspberry Pi Boot Disk Examples

This directory contains example configurations and usage scenarios for the Raspberry Pi Boot Disk project.

## Basic Usage Example

```bash
# 1. Setup the project
./setup.sh

# 2. Download Ubuntu 22.04 LTS for Pi 4
./scripts/download-image.sh

# 3. Create boot disk on SD card (replace /dev/sdb with your device)
sudo ./scripts/create-boot-disk.sh /dev/sdb

# 4. Boot your Pi and enable recovery mode when needed
sudo recovery-mode enable
sudo reboot
```

## Advanced Configuration Examples

### Custom System Name and Larger Recovery Partition

```bash
# Create boot disk with custom name and 8GB recovery partition
sudo ./scripts/create-boot-disk.sh \
  -n "production-server" \
  -s 8 \
  /dev/sdb
```

### Using Specific Ubuntu Version

```bash
# Download Ubuntu 24.04 for Raspberry Pi 5
./scripts/download-image.sh -r 24.04 -t pi5

# Create boot disk with specific image
sudo ./scripts/create-boot-disk.sh \
  -i images/ubuntu-24.04-preinstalled-server-arm64+raspi.img \
  -n "pi5-system" \
  /dev/sdb
```

### Automated Backup Setup

```bash
# After booting into your Pi, set up automatic daily backups
# Add to crontab (crontab -e)
0 2 * * * /usr/local/bin/recovery-tool backup -n "daily-$(date +\%Y\%m\%d)" -c 9

# Weekly full backup
0 3 * * 0 /usr/local/bin/recovery-tool backup -n "weekly-$(date +\%Y\%m\%d)" -f -c 9
```

## Recovery Scenarios

### Scenario 1: System Update Recovery

Before a major system update:

```bash
# Create a backup before update
sudo recovery-mode enable
sudo reboot

# In recovery mode
recovery-tool backup -n "before-system-update" -f

# Return to normal mode
recovery-tool status
# Exit recovery and continue with update
```

If update fails:

```bash
# Boot into recovery
sudo recovery-mode enable
sudo reboot

# Restore pre-update backup
recovery-tool restore -b "before-system-update_*.tar.gz"

# Reboot to restored system
sudo reboot
```

### Scenario 2: Configuration Corruption Recovery

When system won't boot due to configuration issues:

```bash
# Force boot into recovery mode by editing SD card on another computer
# Mount the boot partition and create /boot/recovery_mode file
touch /media/sdcard/boot/recovery_mode

# Boot Pi - it will automatically enter recovery mode
# Restore from latest backup
recovery-tool restore

# Or manually fix configuration files
mkdir -p /mnt/main
mount /dev/mmcblk0p2 /mnt/main
# Edit configuration files in /mnt/main
umount /mnt/main
```

### Scenario 3: Disaster Recovery

Complete system restore from scratch:

```bash
# Boot into recovery mode
recovery-tool status

# List available backups
recovery-tool list

# Restore from specific backup
recovery-tool restore -b "system_backup_20251025_120000.tar.gz"

# Verify restore
recovery-tool logs restore

# Reboot to restored system
sudo reboot
```

## Integration Examples

### Docker Container Recovery

```bash
# Before container updates, create backup
docker stop $(docker ps -q)
recovery-tool backup -n "before-docker-update"

# After update issues
recovery-tool restore -b "before-docker-update_*.tar.gz"
```

### Database Backup Integration

```bash
#!/bin/bash
# Custom backup script with database dump

# Stop database
systemctl stop postgresql

# Create recovery backup
recovery-tool backup -n "with-database-$(date +%Y%m%d)"

# Start database
systemctl start postgresql

echo "Backup with database completed"
```

### Network Boot Recovery

Configure for network-based recovery access:

```bash
# In recovery mode, enable SSH with static IP
cat >> /etc/dhcpcd.conf << EOF
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1
EOF

systemctl restart dhcpcd
systemctl enable ssh
systemctl start ssh

# Now accessible via SSH for remote recovery
```

## Monitoring and Alerting

### Backup Monitoring Script

```bash
#!/bin/bash
# Monitor backup health and send alerts

BACKUP_DIR="/mnt/recovery/backup"
LATEST_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 86400 ))

if [ $BACKUP_AGE -gt 7 ]; then
    echo "WARNING: Latest backup is $BACKUP_AGE days old"
    # Send notification (email, webhook, etc.)
fi
```

### System Health Check

```bash
#!/bin/bash
# Comprehensive system health check

echo "=== System Health Report ==="
echo "Date: $(date)"
echo

echo "=== Recovery System Status ==="
recovery-tool status

echo "=== Disk Usage ==="
df -h

echo "=== Memory Usage ==="
free -h

echo "=== Recent Backups ==="
recovery-tool list | head -10

echo "=== System Load ==="
uptime

echo "=== Recent Logs ==="
journalctl --since "24 hours ago" --priority=err --no-pager | tail -10
```

## Troubleshooting Examples

### Common Issues and Solutions

#### Issue: Recovery mode not activating

```bash
# Debug boot process
mount /dev/mmcblk0p1 /mnt/boot
cat /mnt/boot/boot.log
ls -la /mnt/boot/recovery_mode

# Manual activation
touch /mnt/boot/recovery_mode
umount /mnt/boot
reboot
```

#### Issue: Backup too large for recovery partition

```bash
# Use maximum compression
recovery-tool backup -c 9 -n "compressed-backup"

# Or clean old backups first
recovery-tool clean

# Or exclude unnecessary directories
cd /mnt/recovery/scripts
./backup.sh --exclude="/var/cache/*" --exclude="/tmp/*"
```

#### Issue: Restore fails due to space

```bash
# Check available space
df -h /dev/mmcblk0p2

# Use incremental restore if available
recovery-tool restore --verify-space

# Or expand main partition
parted /dev/mmcblk0 resizepart 2 100%
resize2fs /dev/mmcblk0p2
```

## Performance Optimization

### Fast Backup Configuration

```bash
# Use parallel compression
recovery-tool backup -c 6  # Balanced compression/speed

# Exclude large unnecessary files
cat > /mnt/recovery/backup_exclude.txt << EOF
/var/cache/*
/var/log/journal/*
/tmp/*
*.iso
*.img
*.zip
*.tar.gz
EOF

# Use exclusion list in custom backup
tar --exclude-from=/mnt/recovery/backup_exclude.txt ...
```

### Quick Recovery Setup

```bash
# Pre-configure SSH keys for remote access
mkdir -p /mnt/recovery/ssh_keys
cp ~/.ssh/authorized_keys /mnt/recovery/ssh_keys/

# Auto-enable SSH in recovery mode
echo "systemctl enable ssh" >> /mnt/recovery/recovery_startup.sh
```

These examples demonstrate various real-world scenarios and use cases for the Raspberry Pi Boot Disk project. Adapt them to your specific needs and requirements.