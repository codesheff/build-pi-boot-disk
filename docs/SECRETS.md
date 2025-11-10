# Secrets Management for Cloud-Init Templates

## 🔐 **Overview**

The cloud-init template system now uses a separate `secrets.sh` file to store sensitive information, keeping it secure and separate from the main configuration.

## 📁 **File Structure**

```
cloud-init-templates/
├── config.sh              # Public configuration (non-sensitive)
├── secrets.sh              # Private configuration (sensitive) - GITIGNORED
├── secrets.sh.template     # Template for creating secrets.sh
├── configure-wifi.sh       # WiFi configuration helper (secrets-aware)
└── user-data.template      # Cloud-init user data template
```

## 🚀 **Quick Setup**

### 1. Create Your Secrets File
```bash
cd cloud-init-templates
cp secrets.sh.template secrets.sh
chmod 600 secrets.sh  # Secure permissions
```

### 2. Edit Your Secrets
```bash
nano secrets.sh  # Edit with your actual credentials
```

### 3. Configure WiFi Using Secrets
```bash
# Use WiFi credentials from secrets.sh
./configure-wifi.sh config-both

# Or specify WiFi manually (overrides secrets.sh)
./configure-wifi.sh config-both "MyNetwork" "MyPassword"
```

## 🔒 **What's Stored in Secrets**

### **System Credentials**
- `SECRETS_USERNAME` - Default user account name
- `SECRETS_HOSTNAME` - System hostname
- `SECRETS_PASSWORD_HASH` - Encrypted password hash

### **SSH Configuration**
- `SECRETS_SSH_KEYS` - SSH public keys for authentication

### **WiFi Networks**
- `SECRETS_WIFI_SSID_1` - Primary WiFi network name
- `SECRETS_WIFI_PASSWORD_1` - Primary WiFi password
- `SECRETS_WIFI_HIDDEN_1` - Whether network is hidden
- Additional networks: `_2`, `_3` for backup networks

## 🛠️ **Enhanced WiFi Configuration**

### **Using Secrets (Recommended)**
```bash
# Configure credentials in secrets.sh first, then:
./configure-wifi.sh config-both           # Ethernet + WiFi from secrets
./configure-wifi.sh config-wifi           # WiFi only from secrets
./configure-wifi.sh show-secrets          # Check what's configured
```

### **Manual Override**
```bash
# Still works - overrides secrets.sh
./configure-wifi.sh config-both "NetworkName" "Password"
./configure-wifi.sh config-wifi "HiddenNet" "Pass" --hidden
```

### **View Current Configuration**
```bash
./configure-wifi.sh show-secrets          # Show secrets (redacted)
./configure-wifi.sh show-current          # Show active network config
```

## 🔐 **Security Features**

### **File Protection**
- `secrets.sh` has 600 permissions (owner read/write only)
- Automatically ignored by git (in .gitignore)
- Validation warnings for default/example values

### **Secrets Validation**
The system automatically checks for common security issues:
- Default password hashes
- Example SSH keys
- Example WiFi passwords

### **Redacted Display**
Sensitive information is shown as `***Set***` in status displays.

## 📊 **Migration from Old System**

### **Before (config.sh had everything)**
```bash
# Sensitive data mixed with public config
DEFAULT_PASSWORD_HASH='$5$secret...'
DEFAULT_SSH_KEYS='ssh-rsa AAAAB...'
WIFI_PASSWORD="MySecretPassword"
```

### **After (separated)**
```bash
# config.sh - Public configuration only
DEFAULT_HOSTNAME="${SECRETS_HOSTNAME:-pi-system}"
DEFAULT_USERNAME="${SECRETS_USERNAME:-pi}"

# secrets.sh - Private configuration only
SECRETS_PASSWORD_HASH='$5$secret...'
SECRETS_SSH_KEYS='ssh-rsa AAAAB...'
SECRETS_WIFI_PASSWORD_1="MySecretPassword"
```

## 🎯 **Benefits**

### **Security**
- ✅ Sensitive data separated from public config
- ✅ Automatic git ignore prevents accidental commits
- ✅ File permissions protect from other users
- ✅ Validation catches common security issues

### **Flexibility**
- ✅ Easy WiFi configuration with multiple networks
- ✅ Manual override still available when needed
- ✅ Template system for easy setup
- ✅ Backward compatibility maintained

### **Usability**
- ✅ One-time setup with `secrets.sh`
- ✅ Simple commands: `./configure-wifi.sh config-both`
- ✅ Clear status and validation feedback
- ✅ Comprehensive help and examples

## 🔧 **Integration with Pi Disk Creation**

The `create_pi_disk.sh` script automatically:
1. Sources `config.sh` (which sources `secrets.sh`)
2. Validates secrets configuration
3. Uses secrets for cloud-init file generation
4. Shows warnings for security issues

```bash
# Creates disk with WiFi from secrets.sh
sudo ./create_pi_disk.sh ubuntu-image.img /dev/sdX
```

## 📝 **Example Secrets Configuration**

```bash
# System Configuration
SECRETS_USERNAME="pi"
SECRETS_HOSTNAME="my-pi-system"
SECRETS_PASSWORD_HASH='$5$randomsalt$hashedpassword...'

# SSH Keys (your actual keys)
SECRETS_SSH_KEYS='    - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@laptop
    - ssh-rsa AAAAB3NzaC1yc2EAAAA... user@desktop'

# WiFi Networks
SECRETS_WIFI_SSID_1="HomeNetwork"
SECRETS_WIFI_PASSWORD_1="SecureHomePassword123"
SECRETS_WIFI_HIDDEN_1=false

SECRETS_WIFI_SSID_2="PhoneHotspot"
SECRETS_WIFI_PASSWORD_2="MobilePassword456"
SECRETS_WIFI_HIDDEN_2=false
```

## 🚨 **Security Best Practices**

1. **Never commit secrets.sh** - Always kept in .gitignore
2. **Use strong passwords** - Generate with `openssl passwd -5`
3. **Use your own SSH keys** - Generate with `ssh-keygen -t ed25519`
4. **Secure file permissions** - `chmod 600 secrets.sh`
5. **Regular rotation** - Update passwords and keys periodically
6. **Validation warnings** - Address all validation warnings

The secrets management system provides enterprise-grade security while maintaining the simplicity and automation of the cloud-init template system!