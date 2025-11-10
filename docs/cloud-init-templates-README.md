# Cloud-Init Templates for Pi Disk Creation

This directory contains cloud-init templates that are used to automatically configure Raspberry Pi systems during first boot.

## Files

### Templates
- `user-data.template` - Main cloud-init configuration template
- `meta-data.template` - Instance metadata template  
- `network-config.template` - Network configuration template
- `config.sh` - Public configuration variables (non-sensitive)

### Configuration Files
- `secrets.sh` - Private configuration (passwords, SSH keys, WiFi credentials) - **GITIGNORED**
- `secrets.sh.template` - Template for creating your secrets.sh file

### Helper Scripts
- `configure-wifi.sh` - Interactive WiFi configuration helper (secrets-aware)
- `README.md` - This documentation file
- `SECRETS.md` - Secrets management documentation

## How It Works

When `create_pi_disk.sh` runs, it:

1. **Copies the Ubuntu boot partition** from the source image
2. **Generates cloud-init files** from templates using variables from `config.sh`
3. **Places cloud-init files** on the boot partition where they'll be found during first boot
4. **Continues with root partition setup** and customizations

## Configuration

### 🔐 **Secrets Setup (Required)**
```bash
# 1. Create your secrets file from template
cp secrets.sh.template secrets.sh
chmod 600 secrets.sh

# 2. Edit with your actual credentials
nano secrets.sh

# 3. Configure your sensitive information:
# - Password hashes
# - SSH public keys  
# - WiFi credentials
# - Hostnames/usernames
```

### 📝 **Public Configuration**
Edit `config.sh` for non-sensitive settings:
- Package lists
- Timezone settings  
- Advanced cloud-init options

The system automatically loads secrets from `secrets.sh` when available.

For WiFi, uncomment and modify the WiFi section in `config.sh`.

## Template Variables

Templates use the following substitution variables:

- `{{HOSTNAME}}` - System hostname
- `{{USERNAME}}` - Primary user account name
- `{{PASSWORD_HASH}}` - Encrypted password hash
- `{{SSH_KEYS}}` - SSH authorized keys (YAML formatted)
- `{{NETWORK_CONFIG}}` - Network configuration (YAML formatted)
- `{{TIMESTAMP}}` - Unique timestamp for instance ID

## Security Notes

⚠️ **Important Security Considerations:**

1. **Change the default password hash** in `config.sh`
2. **Add your own SSH keys** and remove the default ones
3. **Use strong passwords** - the default is 'raspberry'
4. **Protect the config.sh file** as it contains password hashes

## Generating Password Hashes

To create a new password hash:

```bash
echo 'your-password' | openssl passwd -5 -stdin
```

## WiFi Configuration

### Easy WiFi Setup (Recommended)

Use the helper script for easy WiFi configuration:

```bash
# WiFi only
./configure-wifi.sh config-wifi "MyNetwork" "MyPassword"

# WiFi + Ethernet  
./configure-wifi.sh config-both "MyNetwork" "MyPassword"

# Hidden network
./configure-wifi.sh config-wifi "HiddenNet" "SecretPass" --hidden

# Reset to Ethernet only
./configure-wifi.sh config-ethernet

# Show current config
./configure-wifi.sh show-current
```

### Manual WiFi Configuration

To manually enable WiFi, modify the `DEFAULT_NETWORK_CONFIG` in `config.sh`:

```bash
# Ethernet + WiFi
DEFAULT_NETWORK_CONFIG='ethernets:
  eth0:
    dhcp4: true
    optional: true
wifis:
  renderer: networkd
  wlan0:
    dhcp4: true
    optional: true
    access-points:
      "YourWiFiNetwork":
        password: "YourWiFiPassword"
        # hidden: true  # Uncomment for hidden networks'

# WiFi only
DEFAULT_NETWORK_CONFIG='wifis:
  renderer: networkd
  wlan0:
    dhcp4: true
    optional: true
    access-points:
      "YourWiFiNetwork":
        password: "YourWiFiPassword"'
```

## What Gets Created

When `create_pi_disk.sh` runs, it generates these files on the boot partition:

- **`user-data`** - System configuration (users, packages, SSH, etc.)
- **`meta-data`** - Instance metadata with unique ID
- **`network-config`** - Network configuration (WiFi/Ethernet)
- **`cmdline.txt`** - Kernel boot parameters (preserved from Ubuntu image)

## First Boot Process

When the Pi boots for the first time:

1. **Kernel loads** using parameters from `cmdline.txt`
2. **Cloud-init runs** and finds the configuration files on the boot partition
3. **System setup** - hostname, users, packages are configured
4. **Network setup** - WiFi/Ethernet is configured based on `network-config`
5. **SSH setup** - SSH keys and service are configured
6. **Cloud-init completes** first-time setup

## Troubleshooting

### Check cloud-init logs on the Pi:
```bash
sudo cloud-init status --long
sudo journalctl -u cloud-init
sudo cat /var/log/cloud-init.log
```

### View generated files:
```bash
# On the created disk (before first boot)
sudo mount /dev/sdX1 /mnt
ls -la /mnt/user-data /mnt/meta-data /mnt/network-config
sudo umount /mnt
```

### Re-run cloud-init (for testing):
```bash
sudo cloud-init clean --logs
sudo cloud-init init
```