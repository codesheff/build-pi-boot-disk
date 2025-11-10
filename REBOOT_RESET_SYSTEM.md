# Reboot-Based Pi Reset System

## Overview

The Pi reset system has been redesigned to use a **reboot-based approach** that eliminates the dangerous practice of manipulating mounted filesystems during operation. This new system schedules the reset to occur during the next boot process, before most services start.

## Why Reboot-Based Reset?

### Problems with the Old Approach
- **Filesystem conflicts**: Trying to replace files while they're in use
- **System instability**: Deleting running executables and libraries
- **Incomplete resets**: Process could fail midway leaving system corrupted
- **Safety issues**: Running from the filesystem being reset

### Benefits of New Approach
- **No filesystem conflicts**: Reset happens before system fully boots
- **Complete safety**: Original system remains untouched until reboot
- **Reliable completion**: Systemd ensures proper service ordering
- **Easy cancellation**: Can cancel reset before rebooting
- **Better logging**: Full operation logged to `/var/log/pi-reset.log`

## How It Works

### 1. Scheduling Phase (`sudo pi-reset.sh`)
```bash
# User runs reset command
sudo pi-reset.sh

# System creates:
# - Reset flag file: /tmp/.pi-reset-scheduled
# - Boot service: /etc/systemd/system/pi-reset-boot.service  
# - Reset script: /usr/local/bin/pi-reset-boot.sh
# - Enables the service for next boot
```

### 2. Boot-Time Reset
```bash
# During next boot:
# 1. systemd starts pi-reset-boot.service early in boot
# 2. Service checks for reset flag
# 3. If flag exists, performs filesystem restore
# 4. Removes flag and disables service
# 5. System continues normal boot with restored state
```

### 3. Service Integration
The reset service is configured to run:
- **After**: `systemd-remount-fs.service` (filesystems available)
- **Before**: Most other services start
- **Target**: `sysinit.target` (very early in boot process)

## Usage Commands

### Schedule a Reset
```bash
sudo pi-reset.sh
# Schedules reset for next boot, offers immediate reboot option
```

### Check Reset Status  
```bash
sudo pi-reset.sh --status
# Shows if reset is scheduled and service status
```

### Cancel Scheduled Reset
```bash
sudo pi-reset.sh --cancel  
# Removes reset flag and service, cancels scheduled reset
```

### Immediate Reboot + Reset
```bash
sudo pi-reset.sh
# Answer 'yes' to schedule, then 'y' to reboot immediately
```

## Technical Implementation

### Files Created
```bash
/tmp/.pi-reset-scheduled                    # Flag file (triggers reset)
/etc/systemd/system/pi-reset-boot.service  # Systemd service
/usr/local/bin/pi-reset-boot.sh            # Boot-time reset script
/var/log/pi-reset.log                      # Reset operation log
```

### Systemd Service Configuration
```ini
[Unit]
Description=Pi Reset Boot Service
DefaultDependencies=no
Conflicts=shutdown.target
After=systemd-remount-fs.service
Before=systemd-sysusers.service systemd-tmpfiles-setup.service
ConditionPathExists=/tmp/.pi-reset-scheduled

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pi-reset-boot.sh
TimeoutSec=0

[Install]
WantedBy=sysinit.target
```

### Reset Process Flow
1. **Service starts** if flag file exists
2. **Mounts both partitions** (backup and active)
3. **Verifies backup integrity** (checks for essential directories)
4. **Performs rsync restore** with proper exclusions
5. **Restores reset scripts** to maintain functionality
6. **Cleans up service files** and removes flag
7. **Logs all operations** for troubleshooting

## Safety Features

### Pre-Reset Validation
- ✅ Checks for backup partition existence
- ✅ Verifies backup partition has system directories
- ✅ Prevents multiple concurrent reset scheduling
- ✅ Requires explicit confirmation

### During Reset
- ✅ Comprehensive logging to `/var/log/pi-reset.log`
- ✅ Proper cleanup on failure or interruption
- ✅ Excludes critical virtual filesystems (`/proc`, `/sys`, etc.)
- ✅ Preserves log file during reset

### Post-Reset
- ✅ Automatically removes reset flag and service
- ✅ Restores reset script functionality for future use
- ✅ Provides detailed operation log

## Error Handling

### Common Scenarios
```bash
# Reset already scheduled
$ sudo pi-reset.sh
[WARNING] A system reset is already scheduled for next boot!
[INFO] Use: sudo pi-reset.sh --cancel    to cancel the reset

# Missing backup partition  
$ sudo pi-reset.sh
[ERROR] Backup partition (LABEL=writable_backup) not found

# Checking status
$ sudo pi-reset.sh --status
[WARNING] System reset is SCHEDULED for next boot
[INFO] Flag file: /tmp/.pi-reset-scheduled
[INFO] Reset service: INSTALLED
```

### Boot-Time Error Recovery
If reset fails during boot:
- Original system remains unchanged (still bootable)
- Error logged to `/var/log/pi-reset.log`
- Service disabled to prevent boot loops
- Flag file removed to prevent retry

## Comparison with Old System

| Aspect | Old System | New System |
|--------|------------|------------|
| **Safety** | ❌ Dangerous | ✅ Safe |
| **Reliability** | ❌ Could fail midway | ✅ Atomic operation |
| **Cancellation** | ❌ Not possible once started | ✅ Can cancel before reboot |
| **Logging** | ❌ Limited | ✅ Comprehensive |
| **Status Check** | ❌ Not available | ✅ Full status reporting |
| **Filesystem Conflicts** | ❌ Major issue | ✅ Eliminated |
| **Recovery** | ❌ Could brick system | ✅ Fail-safe design |

## Integration with Existing Tools

### External Reset Script
The external reset script (`external_pi_reset.sh`) remains unchanged and is still the safest option when available:
```bash
# From external system (preferred method)
sudo ./external_pi_reset.sh /dev/sdb
```

### Workflow Integration
- Works with existing disk creation scripts
- Compatible with dual-partition layout
- Maintains same user interface (`sudo pi-reset.sh`)
- Preserves reset script after restore

## Troubleshooting

### Check Reset Status
```bash
sudo pi-reset.sh --status
systemctl status pi-reset-boot.service
cat /var/log/pi-reset.log
```

### Manual Cleanup (if needed)
```bash
sudo rm -f /tmp/.pi-reset-scheduled
sudo systemctl disable pi-reset-boot.service
sudo rm -f /etc/systemd/system/pi-reset-boot.service
sudo rm -f /usr/local/bin/pi-reset-boot.sh
sudo systemctl daemon-reload
```

### Boot Issues
If system won't boot after failed reset:
1. Boot from external media
2. Check `/var/log/pi-reset.log` on active partition
3. Use external reset script if needed
4. Original backup partition remains intact

## Migration from Old System

Existing Pi systems created with the old reset script will automatically get the new version when:
1. The system is recreated with updated build scripts
2. The reset script is manually updated

The new system is backward compatible - it will work on any dual-partition Pi disk created with the build system.

## Benefits Summary

1. **🛡️ Safe Operation**: No risk of system corruption during reset
2. **🔄 Reliable Process**: Atomic operation that either completes fully or doesn't run
3. **📊 Full Visibility**: Status checking and comprehensive logging
4. **🚫 Easy Cancellation**: Can abort reset before reboot
5. **⚡ Clean Integration**: Uses systemd best practices
6. **🔧 Maintainable**: Clear separation of concerns and error handling
7. **📈 Better UX**: Clear feedback and user control

This reboot-based approach transforms the Pi reset from a dangerous operation into a safe, reliable system maintenance tool.