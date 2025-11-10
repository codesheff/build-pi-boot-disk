# Cloud-Init Templates System# Cloud-Init Templates for Pi Disk Creation



This directory contains a template-based system for generating cloud-init files with secrets management.This directory contains cloud-init templates that are used to automatically configure Raspberry Pi systems during first boot.



## Overview## Files



The template system allows you to:### Templates

- Store cloud-init configurations as templates with placeholders- `user-data.template` - Main cloud-init configuration template

- Keep sensitive information (passwords, SSH keys, WiFi credentials) in a separate secrets file- `meta-data.template` - Instance metadata template  

- Generate the actual cloud-init files by combining templates with secrets- `network-config.template` - Network configuration template

- Maintain version control of templates while keeping secrets secure- `config.sh` - Public configuration variables (non-sensitive)



## Files### Configuration Files

- `secrets.sh` - Private configuration (passwords, SSH keys, WiFi credentials) - **GITIGNORED**

### Templates- `secrets.sh.template` - Template for creating your secrets.sh file

- `user-data.template` - Main cloud-init configuration with user setup

- `meta-data.template` - Instance metadata configuration  ### Helper Scripts

- `network-config.template` - Network configuration (WiFi/Ethernet)- `configure-wifi.sh` - Interactive WiFi configuration helper (secrets-aware)

- `cmdline.txt.template` - Boot parameters- `README.md` - This documentation file

- `SECRETS.md` - Secrets management documentation

### Configuration

- `secrets.env` - Contains sensitive values (passwords, keys, credentials) - **NOT in version control**## How It Works

- `generate-cloud-init-files.sh` - Script to generate files from templates

When `create_pi_disk.sh` runs, it:

## Usage

1. **Copies the Ubuntu boot partition** from the source image

### 1. Setup Secrets2. **Generates cloud-init files** from templates using variables from `config.sh`

Edit the `secrets.env` file with your actual values:3. **Places cloud-init files** on the boot partition where they'll be found during first boot

```bash4. **Continues with root partition setup** and customizations

# Edit secrets with your actual values

nano secrets.env## Configuration

```

### 🔐 **Secrets Setup (Required)**

### 2. Generate Cloud-Init Files```bash

```bash# 1. Create your secrets file from template

# Generate files (with backup of existing)cp secrets.sh.template secrets.sh

./generate-cloud-init-files.sh --backupchmod 600 secrets.sh



# Preview what would be generated# 2. Edit with your actual credentials

./generate-cloud-init-files.sh --dry-runnano secrets.sh



# Generate with custom secrets file# 3. Configure your sensitive information:

./generate-cloud-init-files.sh --secrets-file my-secrets.env# - Password hashes

```# - SSH public keys  

# - WiFi credentials

### 3. Use Generated Files# - Hostnames/usernames

The generated files will be placed in `../cloud-init-files/` and can be used by:```

- `recreate-cloud-init.sh` - Copy files to existing partitions

- `create_pi_disk.sh` - Use during disk creation### 📝 **Public Configuration**

- Manual copying to boot partitionsEdit `config.sh` for non-sensitive settings:

- Package lists

## Template Placeholders- Timezone settings  

- Advanced cloud-init options

The following placeholders are supported in templates:

The system automatically loads secrets from `secrets.sh` when available.

| Placeholder | Description | Example |

|-------------|-------------|---------|For WiFi, uncomment and modify the WiFi section in `config.sh`.

| `{{HOSTNAME}}` | System hostname | `control` |

| `{{USERNAME}}` | User account name | `pi` |## Template Variables

| `{{PASSWORD_HASH}}` | Encrypted password hash | `$5$...` |

| `{{SSH_KEYS}}` | SSH public keys (YAML format) | `    - ssh-rsa ...` |Templates use the following substitution variables:

| `{{WIFI_SSID}}` | WiFi network name | `MyNetwork` |

| `{{WIFI_PASSWORD}}` | WiFi password | `MyPassword123` |- `{{HOSTNAME}}` - System hostname

| `{{WIFI_HIDDEN}}` | WiFi hidden network flag | `true`/`false` |- `{{USERNAME}}` - Primary user account name

| `{{REGDOM}}` | Regulatory domain | `GB` |- `{{PASSWORD_HASH}}` - Encrypted password hash

| `{{INSTANCE_ID}}` | Cloud-init instance ID | `cloud-image` |- `{{SSH_KEYS}}` - SSH authorized keys (YAML formatted)

- `{{NETWORK_CONFIG}}` - Network configuration (YAML formatted)

## Security- `{{TIMESTAMP}}` - Unique timestamp for instance ID



### Important Security Notes## Security Notes

- `secrets.env` is excluded from version control (see .gitignore)

- Never commit actual secrets to version control⚠️ **Important Security Considerations:**

- Keep `secrets.env` file permissions restricted: `chmod 600 secrets.env`

- Use strong passwords and current SSH keys1. **Change the default password hash** in `config.sh`

- Regularly rotate credentials2. **Add your own SSH keys** and remove the default ones

3. **Use strong passwords** - the default is 'raspberry'

### Default Credentials Warning4. **Protect the config.sh file** as it contains password hashes

The default `secrets.env` contains example credentials:

- **Password**: 'raspberry' (change immediately!)## Generating Password Hashes

- **SSH Keys**: Example keys (replace with your own!)

- **WiFi**: Example network (update with real credentials!)To create a new password hash:



## Workflow Integration```bash

echo 'your-password' | openssl passwd -5 -stdin

This template system integrates with the existing cloud-init workflow:```



1. **Development**: Edit templates and test with different secrets## WiFi Configuration

2. **Generation**: Run generation script to create actual files

3. **Deployment**: Use existing scripts (`recreate-cloud-init.sh`, etc.) with generated files### Easy WiFi Setup (Recommended)

4. **Updates**: Modify templates and regenerate as needed

Use the helper script for easy WiFi configuration:

## Example Workflow

```bash

```bash# WiFi only

# 1. Edit secrets for your environment./configure-wifi.sh config-wifi "MyNetwork" "MyPassword"

nano secrets.env

# WiFi + Ethernet  

# 2. Generate cloud-init files./configure-wifi.sh config-both "MyNetwork" "MyPassword"

./generate-cloud-init-files.sh --backup

# Hidden network

# 3. Test the generated files./configure-wifi.sh config-wifi "HiddenNet" "SecretPass" --hidden

cd ../utility

./recreate-cloud-init.sh --dry-run /dev/sda1# Reset to Ethernet only

./configure-wifi.sh config-ethernet

# 4. Apply to actual partition

./recreate-cloud-init.sh /dev/sda1# Show current config

```./configure-wifi.sh show-current

```

## Backup and Recovery

### Manual WiFi Configuration

The generation script automatically creates backups:

- `--backup` flag creates timestamped backupsTo manually enable WiFi, modify the `DEFAULT_NETWORK_CONFIG` in `config.sh`:

- Backups are stored as `../cloud-init-files.backup-YYYYMMDD-HHMMSS`

- Original files are preserved before generation```bash

# Ethernet + WiFi

## ValidationDEFAULT_NETWORK_CONFIG='ethernets:

  eth0:

The generation script includes validation:    dhcp4: true

- Checks for missing secret variables    optional: true

- Validates generated file sizeswifis:

- Detects unsubstituted placeholders  renderer: networkd

- Compares against expected file sizes  wlan0:

    dhcp4: true

## File Comparison    optional: true

    access-points:

After generation, you can verify the files are identical to your reference:      "YourWiFiNetwork":

```bash        password: "YourWiFiPassword"

# Compare generated files to backup        # hidden: true  # Uncomment for hidden networks'

diff -r ../cloud-init-files.backup ../cloud-init-files --exclude="README.md"

```# WiFi only

DEFAULT_NETWORK_CONFIG='wifis:

## Troubleshooting  renderer: networkd

  wlan0:

### Common Issues    dhcp4: true

1. **Missing placeholders**: Check that all required variables are in `secrets.env`    optional: true

2. **File size mismatches**: Verify template placeholders match secrets    access-points:

3. **Permission errors**: Ensure `secrets.env` is readable      "YourWiFiNetwork":

4. **Generation fails**: Check template syntax and file permissions        password: "YourWiFiPassword"'

```

### Debugging

```bash## What Gets Created

# Show what would be generated

./generate-cloud-init-files.sh --dry-runWhen `create_pi_disk.sh` runs, it generates these files on the boot partition:



# Check secrets loading- **`user-data`** - System configuration (users, packages, SSH, etc.)

grep "SUCCESS.*Loaded" <(./generate-cloud-init-files.sh --dry-run)- **`meta-data`** - Instance metadata with unique ID

- **`network-config`** - Network configuration (WiFi/Ethernet)

# Validate templates- **`cmdline.txt`** - Kernel boot parameters (preserved from Ubuntu image)

grep -r "{{.*}}" *.template

```## First Boot Process



This template system provides a secure, maintainable way to manage cloud-init configurations while keeping sensitive information separate from version control.When the Pi boots for the first time:

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