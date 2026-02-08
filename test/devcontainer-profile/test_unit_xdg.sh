#!/bin/bash
set -o errexit
set -o pipefail

source "$(dirname "$0")/test_utils.sh"
setup_hermetic_env

cleanup() {
    echo ">>> Final Profile Log: unit xdg test"
    cat "$LOG_FILE" 2>/dev/null || echo "(Log file empty or missing)"
    teardown_hermetic_env
}
trap cleanup EXIT

echo "=== [Unit] XDG Discovery Tests ==="

# Mock sudo
mock_tool "sudo"

# Helper to run discovery only (we source the script function if possible, 
# or run the script and check what file ends up in VOLUME_CONFIG_DIR)

run_discovery() {
    # Clear previous state
    rm -f "$VOLUME_CONFIG_DIR/config.json"
    "$INSTALL_DIR/scripts/apply.sh"
}

# 1. Test: Implicit Config (baked in image)
mkdir -p "$HOME/.devcontainer.profile"
echo '{"test": "test-baked"}' > "$HOME/.devcontainer.profile/config.json"
run_discovery
if grep -q "test-baked" "$VOLUME_CONFIG_DIR/config.json"; then
    log_pass "Found ~/.devcontainer.profile/config.json"
else
    log_fail "Failed to find home directory config"
fi

# 2. Test: XDG Config Home
mkdir -p "$HOME/.config/devcontainer-profile"
echo '{"test": "test-xdg"}' > "$HOME/.config/devcontainer-profile/config.json"
run_discovery
if grep -q "test-xdg" "$VOLUME_CONFIG_DIR/config.json"; then
    log_pass "Found ~/.config/devcontainer-profile/config.json (Precedence over home)"
else
    log_fail "XDG config did not override home config"
fi

# 3. Test: Bind Mount (Highest Priority)
mkdir -p "$WORKSPACE/.config/.devcontainer-profile"
echo '{"test": "test-mount"}' > "$WORKSPACE/.config/.devcontainer-profile/config.json"
run_discovery
if grep -q "test-mount" "$VOLUME_CONFIG_DIR/config.json"; then
    log_pass "Found Bind Mount config (Highest priority)"
else
    log_fail "Bind mount did not override others"
fi

echo "=== XDG Tests Passed ==="
