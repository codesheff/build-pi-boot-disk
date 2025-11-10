#!/bin/bash
# Integration test for recreate-cloud-init.sh script

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() { echo -e "${GREEN}[TEST PASS]${NC} $1"; }
print_fail() { echo -e "${RED}[TEST FAIL]${NC} $1"; }
print_info() { echo -e "${YELLOW}[TEST INFO]${NC} $1"; }

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RECREATE_SCRIPT="$SCRIPT_DIR/recreate-cloud-init.sh"
TEST_DIR="/tmp/recreate-cloud-init-test"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Manual cleanup at the end of tests instead of trap

# Test 1: Help functionality
print_info "Test 1: Help functionality"
if "$RECREATE_SCRIPT" --help >/dev/null 2>&1; then
    print_success "Help output works"
else
    print_fail "Help output failed"
    exit 1
fi

# Test 2: Dry run functionality
print_info "Test 2: Dry run functionality"
mkdir -p "$TEST_DIR"
"$RECREATE_SCRIPT" --dry-run "$TEST_DIR" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    print_success "Dry run works"
else
    print_fail "Dry run failed"
    exit 1
fi

# Test 3: Basic file generation
print_info "Test 3: Basic file generation"
"$RECREATE_SCRIPT" --force "$TEST_DIR" test-host test-user >/dev/null 2>&1 || true

# Check if all expected files were created
if [[ -f "$TEST_DIR/user-data" && -f "$TEST_DIR/meta-data" && -f "$TEST_DIR/network-config" && -f "$TEST_DIR/cmdline.txt" ]]; then
    print_success "All cloud-init files generated"
else
    print_fail "Not all files generated"
    ls -la "$TEST_DIR"
    exit 1
fi

# Test 4: Custom hostname in generated files
print_info "Test 4: Custom hostname verification"
# The files should contain the hostname from test 3 (test-host)
if [[ -f "$TEST_DIR/user-data" && -f "$TEST_DIR/meta-data" ]]; then
    if grep -q "hostname: test-host" "$TEST_DIR/user-data" && 
       grep -q "test-host" "$TEST_DIR/meta-data"; then
        print_success "Custom hostname correctly applied"
    else
        print_fail "Custom hostname not found in generated files"
        echo "Found in user-data:" && grep "hostname:" "$TEST_DIR/user-data" || echo "No hostname found"
        echo "Found in meta-data:" && grep -E "(hostname|instance)" "$TEST_DIR/meta-data" || echo "No hostname found"
        exit 1
    fi
else
    print_fail "user-data or meta-data files missing"
    exit 1
fi

# Test 5: Backup functionality
print_info "Test 5: Backup functionality"
# Create some existing files to overwrite the generated ones
echo "existing user-data" > "$TEST_DIR/user-data"
echo "existing meta-data" > "$TEST_DIR/meta-data"

if "$RECREATE_SCRIPT" --backup --force "$TEST_DIR" backup-test >/dev/null 2>&1; then
    # Check if backup directory was created
    if find "$TEST_DIR" -name ".cloud-init-backup-*" -type d | grep -q "backup"; then
        print_success "Backup functionality works"
    else
        print_fail "No backup directory created"
        exit 1
    fi
    
    # Verify the files were actually regenerated (should be larger than "existing user-data")
    if [[ $(stat -c%s "$TEST_DIR/user-data") -gt 100 ]]; then
        print_success "Files were properly regenerated after backup"
    else
        print_fail "Files were not properly regenerated after backup"
        exit 1
    fi
else
    print_fail "Backup functionality failed - script returned error"
    exit 1
fi

# Test 6: Network config generation
print_info "Test 6: Network configuration"
if [[ -f "$TEST_DIR/network-config" ]] && [[ -s "$TEST_DIR/network-config" ]]; then
    print_success "Network configuration generated"
else
    print_fail "Network configuration missing or empty"
    exit 1
fi

# Test 7: SSH keys in user-data (check backup-test generated files)
print_info "Test 7: SSH keys in user-data"
if grep -q "ssh_authorized_keys:" "$TEST_DIR/user-data" && 
   grep -q "ssh-rsa" "$TEST_DIR/user-data"; then
    print_success "SSH keys included in user-data"
else
    print_fail "SSH keys missing from user-data"
    exit 1
fi

# Test 8: Password hash in user-data (check backup-test generated files)
print_info "Test 8: Password hash in user-data"
if grep -q "passwd:" "$TEST_DIR/user-data" && 
   grep -q '\$5\$' "$TEST_DIR/user-data"; then
    print_success "Password hash included in user-data"
else
    print_fail "Password hash missing from user-data"
    exit 1
fi

print_success "All tests passed! The recreate-cloud-init.sh script is working correctly."
print_info "Generated files location: $TEST_DIR"
print_info "You can examine the generated files manually if needed."

# Clean up test directory
cleanup