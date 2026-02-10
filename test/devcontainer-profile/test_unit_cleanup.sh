#!/bin/bash
set -o errexit
set -o pipefail

source "$(dirname "$0")/test_utils.sh"
setup_hermetic_env

cleanup() {
    echo ">>> Final Profile Log: unit cleanup test"
    cat "$LOG_FILE" 2>/dev/null || echo "(Log file empty or missing)"
    teardown_hermetic_env
}
trap cleanup EXIT

echo "=== [Unit] Managed Resource Cleanup Tests ==="

# Mock dependencies
mock_tool "sudo"

# Helper for configs
write_config() {
    echo "$1" > "$USER_CONFIG_PATH"
}

# Test 1: Link Creation & Tracking
echo "--- Test 1: Link Creation ---"
mkdir -p "$HOME/sources"
touch "$HOME/sources/file1.txt"

write_config '{
    "files": [
        { "source": "~/sources/file1.txt", "target": "~/.file1" }
    ]
}'

# Run Engine
"$INSTALL_DIR/scripts/apply.sh"

assert_file_exists "$HOME/.file1"
STATE_FILE="${STATE_DIR}/managed_symlinks.list"
if grep -qF "$HOME/.file1" "$STATE_FILE"; then
    log_pass "Link tracked in state file"
else
    log_fail "Link NOT found in state file"
fi

# Test 2: Stale Link Pruning
echo "--- Test 2: Stale Link Pruning ---"
# Remove the file from config
write_config '{ "files": [] }'

# Run Engine
"$INSTALL_DIR/scripts/apply.sh"

if [[ ! -L "$HOME/.file1" ]]; then
    log_pass "Stale link pruned correctly"
else
    log_fail "Stale link still exists"
fi

if ! grep -qF "$HOME/.file1" "$STATE_FILE" 2>/dev/null; then
    log_pass "Link removed from state file"
else
    log_fail "Link still in state file"
fi

# Test 3: User Resource Preservation
echo "--- Test 3: User Resource Preservation ---"
# Manually create a symlink NOT managed by us
ln -s "$HOME/sources/file1.txt" "$HOME/.user_link"

write_config '{ "files": [] }'
"$INSTALL_DIR/scripts/apply.sh"

if [[ -L "$HOME/.user_link" ]]; then
    log_pass "User-created link preserved"
else
    log_fail "User-created link was accidentally deleted"
fi

# Test 4: Re-linking Existing but Changed
echo "--- Test 4: Re-linking ---"
touch "$HOME/sources/file2.txt"
write_config '{
    "files": [
        { "source": "~/sources/file2.txt", "target": "~/.file1" }
    ]
}'
"$INSTALL_DIR/scripts/apply.sh"

assert_file_exists "$HOME/.file1"
TARGET=$(readlink -f "$HOME/.file1")
if [[ "$TARGET" == "$HOME/sources/file2.txt" ]]; then
    log_pass "Re-linked to new source correctly"
else
    log_fail "Link points to wrong target: $TARGET"
fi

echo "=== Cleanup Tests Passed ==="
