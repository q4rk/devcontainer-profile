#!/bin/bash
# test_utils.sh
# Shared library for Hermetic Unit Testing of devcontainer-profile

set -o nounset
set -o pipefail

# --- Setup & Teardown ---

setup_hermetic_env() {
    # Create a sandbox directory
    export TEST_ROOT
    TEST_ROOT=$(mktemp -d)
    
    # Define standard paths relative to the sandbox
    export HOME="$TEST_ROOT/home"
    export WORKSPACE="$TEST_ROOT/workspace"
    export STATE_DIR="$WORKSPACE/state"
    export LOG_FILE="$STATE_DIR/profile.log"
    export AUDIT_LOG="$TEST_ROOT/audit.json"
    
    # Engine specific vars
    export TARGET_USER="$(id -un)"
    export TARGET_HOME="$HOME"
    export MANAGED_CONFIG_DIR="$HOME/.devcontainer-profile"
    export VOLUME_CONFIG_DIR="$STATE_DIR/configs"
    export USER_CONFIG_PATH="$VOLUME_CONFIG_DIR/config.json"
    export INSTANCE_MARKER="$HOME/.devcontainer-profile.applied"
    
    # Create structure
    mkdir -p "$HOME" "$STATE_DIR" "$VOLUME_CONFIG_DIR" "$WORKSPACE/tmp"
    
    # Copy Source Code to Test Root (Hermetic)
    # Allows testing local changes without installing them
    local REPO_ROOT=""
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local possible_repo_root="${script_dir}/../../src/devcontainer-profile"
    
    if [[ -d "${possible_repo_root}" ]]; then
        REPO_ROOT="$(cd "${possible_repo_root}" && pwd)"
    fi
    
    export INSTALL_DIR="$TEST_ROOT/install"
    mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/plugins" "$INSTALL_DIR/lib"
    
    if [[ -n "${REPO_ROOT}" && -d "${REPO_ROOT}/scripts" ]]; then
        cp "${REPO_ROOT}/scripts/apply.sh" "$INSTALL_DIR/scripts/"
        cp "${REPO_ROOT}/scripts/lib/utils.sh" "$INSTALL_DIR/lib/"
        cp "${REPO_ROOT}/scripts/plugins/"*.sh "$INSTALL_DIR/plugins/"
    else
        # Fallback to installed assets if src is not available
        local installed_base="/usr/local/share/devcontainer-profile"
        if [[ -d "${installed_base}" ]]; then
            cp "${installed_base}/scripts/apply.sh" "$INSTALL_DIR/scripts/"
            cp "${installed_base}/lib/utils.sh" "$INSTALL_DIR/lib/"
            cp "${installed_base}/plugins/"*.sh "$INSTALL_DIR/plugins/"
        else
            echo "(!) FATAL: Could not find source or installed assets to test." >&2
            return 1
        fi
    fi
    
    chmod +x "$INSTALL_DIR/scripts/apply.sh"
    chmod +x "$INSTALL_DIR/plugins/"*.sh
    
    # Point the engine to our sandboxed library
    export LIB_PATH="$INSTALL_DIR/lib/utils.sh"
    export PLUGIN_DIR="$INSTALL_DIR/plugins"
    
    # Setup Mock Binaries
    export MOCK_BIN="$TEST_ROOT/bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
}

teardown_hermetic_env() {
    if [[ -n "${TEST_ROOT:-}" ]] && [[ -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

# --- Mocking System ---

# Generates a mock that logs calls to AUDIT_LOG in JSON format
mock_tool() {
    local name="$1"
    local bin_path="$MOCK_BIN/$name"
    
    cat <<EOF > "$bin_path"
#!/bin/bash
# Mock for $name
args_json=\$(printf '%s\n' "\$@" | jq -R . | jq -s .)
cwd=\$(pwd)
timestamp=\$(date +%s)

# Append JSON log entry
cat <<JSON >> "$AUDIT_LOG"
{"tool": "$name", "args": \$args_json, "cwd": "\$cwd", "ts": \$timestamp}
JSON

# If special behavior is needed, add it here
if [[ "$name" == "sudo" ]]; then
    while [[ "\$1" == -* ]]; do
        if [[ "\$1" == "-u" ]]; then
            shift 2
        else
            shift 1
        fi
    done
    "\$@"
fi
EOF
    chmod +x "$bin_path"
}

# --- Assertions ---

log_pass() { echo -e "  \e[32m[PASS]\e[0m $1"; }
log_fail() { 
    echo -e "  \e[31m[FAIL]\e[0m $1"; 
    echo ">>> Profile Log Dump (on failure):"
    cat "${LOG_FILE:-/dev/null}" 2>/dev/null || echo "(Log file empty or missing)"
    exit 1; 
}

assert_file_exists() {
    if [[ -f "$1" || -L "$1" ]]; then
        log_pass "File exists: $1"
    else
        log_fail "File missing: $1"
    fi
}

assert_audit_call() {
    local tool="$1"
    local arg_signature="$2" # jq filter for args
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        log_fail "Audit log not found (no mocks called)"
    fi
    
    # Look for the call in the JSON log
    local count
    count=$(jq -c "select(.tool == \"$tool\") | select(.args | $arg_signature)" "$AUDIT_LOG" | wc -l)
    
    if [[ "$count" -gt 0 ]]; then
        log_pass "Mock Called: $tool (Signature matched)"
    else
        echo "Dumping Audit Log for Context:"
        cat "$AUDIT_LOG"
        log_fail "Mock Call Missing: $tool matching $arg_signature"
    fi
}