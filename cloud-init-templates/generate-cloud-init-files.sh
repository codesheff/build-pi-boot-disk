#!/bin/bash
# Generate Cloud-Init Files from Templates and Secrets
# This script recreates cloud-init-files/ from templates and secrets.env

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Paths
TEMPLATES_DIR="$SCRIPT_DIR"
SECRETS_FILE="$TEMPLATES_DIR/secrets.env"
OUTPUT_DIR="$PROJECT_ROOT/cloud-init-files"

show_usage() {
    echo "Generate Cloud-Init Files from Templates"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --secrets-file FILE    Path to secrets.env file (default: ./secrets.env)"
    echo "  --output-dir DIR       Output directory (default: ../cloud-init-files)"
    echo "  --backup              Create backup of existing output directory"
    echo "  --force               Overwrite existing files without confirmation"
    echo "  --dry-run             Show what would be generated without making changes"
    echo "  --help, -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Generate with default settings"
    echo "  $0 --backup                          # Generate with backup of existing files"
    echo "  $0 --dry-run                         # Preview what would be generated"
    echo "  $0 --secrets-file custom.env         # Use custom secrets file"
    echo ""
    echo "The script will:"
    echo "  1. Load secrets from secrets.env"
    echo "  2. Process template files with placeholder substitution"
    echo "  3. Generate cloud-init files in the output directory"
    echo "  4. Validate generated files"
}

# Function to load secrets from env file
load_secrets() {
    local secrets_file="$1"
    
    if [[ ! -f "$secrets_file" ]]; then
        print_error "Secrets file not found: $secrets_file"
        return 1
    fi
    
    print_info "Loading secrets from: $secrets_file"
    
    # Source the secrets file
    set -a  # Export all variables
    source "$secrets_file"
    set +a  # Stop exporting
    
    # Validate required variables
    local required_vars=(
        "HOSTNAME" "USERNAME" "PASSWORD_HASH" "SSH_KEYS"
        "WIFI_SSID" "WIFI_PASSWORD" "WIFI_HIDDEN"
        "REGDOM" "INSTANCE_ID"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required variables in secrets file:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    
    print_success "Loaded ${#required_vars[@]} secret variables"
}

# Function to substitute template variables
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$template_file" ]]; then
        print_error "Template file not found: $template_file"
        return 1
    fi
    
    print_info "Processing template: $(basename "$template_file")"
    
    # Use envsubst to substitute variables, but handle special cases
    local temp_content
    temp_content=$(cat "$template_file")
    
    # Handle special substitutions that need bash expansion
    temp_content="${temp_content//\{\{HOSTNAME\}\}/$HOSTNAME}"
    temp_content="${temp_content//\{\{USERNAME\}\}/$USERNAME}"
    temp_content="${temp_content//\{\{PASSWORD_HASH\}\}/$PASSWORD_HASH}"
    temp_content="${temp_content//\{\{SSH_KEYS\}\}/$SSH_KEYS}"
    temp_content="${temp_content//\{\{WIFI_SSID\}\}/$WIFI_SSID}"
    temp_content="${temp_content//\{\{WIFI_PASSWORD\}\}/$WIFI_PASSWORD}"
    temp_content="${temp_content//\{\{WIFI_HIDDEN\}\}/$WIFI_HIDDEN}"
    temp_content="${temp_content//\{\{REGDOM\}\}/$REGDOM}"
    temp_content="${temp_content//\{\{INSTANCE_ID\}\}/$INSTANCE_ID}"
    
    echo "$temp_content" > "$output_file"
    
    print_success "Generated: $(basename "$output_file")"
}

# Function to backup existing directory
backup_existing() {
    local dir="$1"
    
    if [[ -d "$dir" ]]; then
        local backup_dir="${dir}.backup-$(date +%Y%m%d-%H%M%S)"
        print_info "Creating backup: $backup_dir"
        cp -r "$dir" "$backup_dir"
        print_success "Backup created"
    fi
}

# Function to show what would be generated
show_dry_run() {
    print_info "DRY RUN: Would generate the following files:"
    echo ""
    
    local templates=(
        "user-data.template:user-data"
        "meta-data.template:meta-data"
        "network-config.template:network-config"
        "cmdline.txt.template:cmdline.txt"
    )
    
    for template_mapping in "${templates[@]}"; do
        local template_name="${template_mapping%%:*}"
        local output_name="${template_mapping##*:}"
        local template_file="$TEMPLATES_DIR/$template_name"
        
        if [[ -f "$template_file" ]]; then
            echo "  ✓ $template_name → $output_name"
            echo "    Variables that would be substituted:"
            grep -o '{{[^}]*}}' "$template_file" | sort -u | sed 's/^/      - /' || true
        else
            echo "  ✗ $template_name (not found)"
        fi
        echo ""
    done
    
    print_info "Output directory: $OUTPUT_DIR"
    print_info "Secrets file: $SECRETS_FILE"
}

# Function to validate generated files
validate_generated_files() {
    local output_dir="$1"
    
    print_info "Validating generated files..."
    
    local required_files=("user-data" "meta-data" "network-config" "cmdline.txt")
    local validation_passed=true
    
    for file in "${required_files[@]}"; do
        local file_path="$output_dir/$file"
        if [[ -f "$file_path" ]]; then
            local size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
            if [[ $size -gt 0 ]]; then
                print_success "✓ $file ($size bytes)"
            else
                print_error "✗ $file (empty file)"
                validation_passed=false
            fi
        else
            print_error "✗ $file (missing)"
            validation_passed=false
        fi
    done
    
    # Check for remaining template placeholders
    for file in "${required_files[@]}"; do
        local file_path="$output_dir/$file"
        if [[ -f "$file_path" ]] && grep -q '{{.*}}' "$file_path" 2>/dev/null; then
            print_warning "⚠ $file contains unsubstituted placeholders:"
            grep -o '{{[^}]*}}' "$file_path" | sort -u | sed 's/^/    /'
            validation_passed=false
        fi
    done
    
    if [[ "$validation_passed" == "true" ]]; then
        print_success "All files validated successfully"
        return 0
    else
        print_error "Validation failed"
        return 1
    fi
}

# Function to confirm operation
confirm_operation() {
    local output_dir="$1"
    
    if [[ -d "$output_dir" ]]; then
        print_warning "Output directory exists: $output_dir"
        print_warning "Existing files will be overwritten"
        echo ""
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled by user"
            return 1
        fi
    fi
    return 0
}

# Main function
main() {
    local secrets_file="$SECRETS_FILE"
    local output_dir="$OUTPUT_DIR"
    local backup="false"
    local force="false"
    local dry_run="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --secrets-file)
                if [[ -z "${2:-}" ]]; then
                    print_error "--secrets-file requires a file path"
                    exit 1
                fi
                secrets_file="$2"
                shift 2
                ;;
            --output-dir)
                if [[ -z "${2:-}" ]]; then
                    print_error "--output-dir requires a directory path"
                    exit 1
                fi
                output_dir="$2"
                shift 2
                ;;
            --backup)
                backup="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                print_error "Unexpected argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_info "Cloud-Init Files Generation Starting..."
    print_info "Templates directory: $TEMPLATES_DIR"
    print_info "Secrets file: $secrets_file"
    print_info "Output directory: $output_dir"
    echo ""
    
    # Load secrets
    if ! load_secrets "$secrets_file"; then
        exit 1
    fi
    
    # Show dry run if requested
    if [[ "$dry_run" == "true" ]]; then
        show_dry_run
        print_info "Dry run completed - no files generated"
        exit 0
    fi
    
    # Confirm operation unless forced
    if [[ "$force" != "true" ]]; then
        if ! confirm_operation "$output_dir"; then
            exit 0
        fi
    fi
    
    # Backup existing files if requested
    if [[ "$backup" == "true" ]]; then
        backup_existing "$output_dir"
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Process templates
    local templates=(
        "user-data.template:user-data"
        "meta-data.template:meta-data"
        "network-config.template:network-config"
        "cmdline.txt.template:cmdline.txt"
    )
    
    for template_mapping in "${templates[@]}"; do
        local template_name="${template_mapping%%:*}"
        local output_name="${template_mapping##*:}"
        local template_file="$TEMPLATES_DIR/$template_name"
        local output_file="$output_dir/$output_name"
        
        if ! substitute_template "$template_file" "$output_file"; then
            print_error "Failed to process template: $template_name"
            exit 1
        fi
    done
    
    echo ""
    print_success "Cloud-init files generated successfully!"
    
    # Validate generated files
    if ! validate_generated_files "$output_dir"; then
        print_error "File validation failed"
        exit 1
    fi
    
    echo ""
    print_success "Generation completed successfully!"
    print_info "Files are ready in: $output_dir"
}

main "$@"