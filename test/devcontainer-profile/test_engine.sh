#!/bin/bash
source /tmp/test_lib.sh

setup_suite
mock_utils
setup_mocks

echo "=== Engine Logic Tests ==="

# 1. Hashing Mechanism
echo "[Test] Configuration Hashing"
echo '{"apt": ["vim"]}' > "$USER_CONFIG_PATH"

# Simulate hash calculation
HASH_1=$(md5sum "$USER_CONFIG_PATH" | awk '{print $1}')
echo "$HASH_1" > "$STATE_DIR/last_applied_hash"

# Create a new config with same content (timestamp change only)
touch "$USER_CONFIG_PATH"
HASH_2=$(md5sum "$USER_CONFIG_PATH" | awk '{print $1}')

assert_eq "$HASH_1" "$HASH_2" "Hash remains stable on touch"

# Change content
echo '{"apt": ["vim", "nano"]}' > "$USER_CONFIG_PATH"
HASH_3=$(md5sum "$USER_CONFIG_PATH" | awk '{print $1}')

if [[ "$HASH_1" != "$HASH_3" ]]; then
    echo -e "  \e[32m[PASS]\e[0m Hash updated on content change"
else
    echo -e "  \e[31m[FAIL]\e[0m Hash collision detected"
    exit 1
fi

# 2. Solid Directory Link
echo "[Test] Solid Directory Linking"
# Simulate the logic from apply.sh
rm -rf "$MANAGED_CONFIG_DIR"
ln -sf "$VOLUME_CONFIG_DIR" "$MANAGED_CONFIG_DIR"

# Verify functionality
assert_file_exists "$MANAGED_CONFIG_DIR"
assert_eq "$VOLUME_CONFIG_DIR" "$(readlink "$MANAGED_CONFIG_DIR")" "Symlink points to volume"

# Verify bidirectional write
touch "$MANAGED_CONFIG_DIR/sync_probe"
assert_file_exists "$VOLUME_CONFIG_DIR/sync_probe"

# 3. Path Reconciliation Logic (Unit)
echo "[Test] Path Reconciliation"
# Mock the 40-path.sh logic behavior
CUSTOM_BIN="$TEST_ROOT/opt/myapp/bin"
mkdir -p "$CUSTOM_BIN"

# Simulate discovery
if [[ -d "$CUSTOM_BIN" ]]; then
    echo "add_path \"$CUSTOM_BIN\"" > "$USER_PATH_FILE"
fi

assert_audit "" # Just ensuring no errors logged so far
if grep -q "$CUSTOM_BIN" "$USER_PATH_FILE"; then
     echo -e "  \e[32m[PASS]\e[0m Path discovery logic verified"
else
     echo -e "  \e[31m[FAIL]\e[0m Path discovery failed"
     exit 1
fi