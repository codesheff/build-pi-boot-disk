# Cloud-Init Files Comparison Script

## 📊 **Purpose**
The `compare-cloud-init.sh` script provides comprehensive comparison of cloud-init files between two filesystems, making it easy to verify that Pi disk creation produces the expected configuration files.

## 🛠️ **Features**

### **Supported Files**
- `user-data` - Main cloud-init system configuration
- `meta-data` - Instance metadata and datasource configuration  
- `network-config` - Network configuration (WiFi/Ethernet)
- `cmdline.txt` - Kernel boot parameters

### **Comparison Types**
- **File Size Comparison** - Quick overview of file sizes
- **Content Comparison** - Detects if files are identical or different
- **Detailed Diff** - Shows exact line-by-line differences
- **Side-by-Side View** - Visual comparison of file contents

### **Filesystem Support**
- **Block Devices** - `/dev/sda1`, `/dev/mmcblk0p1`, etc. (auto-mounted)
- **Mount Points** - `/mnt/disk1`, `/boot/firmware`, etc.
- **Directories** - Any directory containing cloud-init files

## 📝 **Usage Examples**

### Basic Comparison
```bash
# Compare our created disk with original Pi disk
./compare-cloud-init.sh /dev/sda1 /dev/mmcblk0p1

# Compare using mount points (more reliable)
./compare-cloud-init.sh /mnt/sda1 /boot/firmware
```

### Detailed Analysis
```bash
# Show detailed differences with diff output
./compare-cloud-init.sh --detailed /mnt/sda1 /boot/firmware

# Compare only specific files
./compare-cloud-init.sh --files user-data,network-config /mnt/sda1 /boot/firmware
```

### Summary Only
```bash
# Quick size and status overview
./compare-cloud-init.sh --summary /mnt/sda1 /boot/firmware
```

## 📊 **Sample Output Analysis**

### **Current Comparison Results** (/dev/sda1 vs /dev/mmcblk0p1):

```
=== File Size Comparison ===
  △ user-data: 1485 vs 3891 bytes (different)      # Our template is 62% smaller
  △ meta-data: 932 vs 921 bytes (different)        # Unique instance ID added  
  △ network-config: 358 vs 222 bytes (different)   # Better network config
  ✗ cmdline.txt: MISSING vs 29 bytes               # Need to preserve this
```

### **Key Differences Found**:

#### **user-data improvements** ✅
- **Size**: 62% smaller (1485 vs 3891 bytes)
- **SSH Keys**: Fixed duplication (1 key vs 6 duplicates)
- **Packages**: Added essential tools (curl, wget, git, vim, htop)
- **Documentation**: Better comments and structure
- **SSH Config**: Added proper SSH service configuration

#### **meta-data improvements** ✅  
- **Instance ID**: Unique timestamp vs generic "cloud-image"
- **Size**: Slightly larger due to better documentation

#### **network-config improvements** ✅
- **Default**: Ethernet DHCP (universal) vs WiFi-only (limited)
- **Security**: Template-based vs hardcoded WiFi credentials
- **Documentation**: Clear examples for WiFi configuration

#### **cmdline.txt missing** ⚠️
- **Issue**: Our disk doesn't have cmdline.txt (regional settings)
- **Impact**: Missing `cfg80211.ieee80211_regdom=GB`
- **Status**: Fixed in enhanced create_pi_disk.sh script

## 🎯 **Practical Use Cases**

### **Quality Assurance**
```bash
# Verify disk creation worked correctly
./compare-cloud-init.sh /dev/sdX1 /boot/firmware

# Check specific file was updated correctly  
./compare-cloud-init.sh --files network-config /dev/sdX1 /boot/firmware
```

### **Debugging**
```bash
# See exact differences when troubleshooting
./compare-cloud-init.sh --detailed /mnt/new-disk /mnt/working-disk

# Compare before/after configuration changes
./compare-cloud-init.sh /mnt/before /mnt/after
```

### **Documentation**
```bash
# Generate comparison report for documentation
./compare-cloud-init.sh --detailed /dev/sda1 /dev/mmcblk0p1 > comparison-report.txt
```

## 🔧 **Technical Details**

### **Color-Coded Output**
- 🟢 **Green ✓**: Files are identical
- 🟡 **Yellow △**: Files differ (size or content)  
- 🔴 **Red ✗**: File missing from one filesystem

### **Auto-Mounting**
- Automatically mounts block devices to temporary directories
- Uses existing mount points when available
- Cleans up temporary mounts when done

### **Error Handling**
- Validates filesystem paths before comparison
- Handles missing files gracefully
- Reports mounting errors clearly

## 📈 **Integration with Pi Disk Workflow**

The comparison script integrates perfectly with the Pi disk creation workflow:

```bash
# 1. Create a new Pi disk
sudo ./create_pi_disk.sh ubuntu-image.img /dev/sdX

# 2. Compare with reference system
./compare-cloud-init.sh /dev/sdX1 /boot/firmware

# 3. Verify specific configurations
./compare-cloud-init.sh --files network-config /dev/sdX1 /boot/firmware

# 4. Debug any issues with detailed output
./compare-cloud-init.sh --detailed /dev/sdX1 /boot/firmware
```

This provides complete visibility into what cloud-init files are created and how they differ from the reference system, ensuring quality and consistency in Pi disk creation.