#!/usr/bin/env bash
set -e

# Import Microsoft's test library for the basic checks
source dev-container-features-test-lib

# --- 1. Basic Static Analysis ---
check "apply.sh exists" ls /usr/local/share/devcontainer-profile/scripts/apply.sh
check "plugins exist" ls /usr/local/share/devcontainer-profile/plugins/10-apt.sh

# --- 2. Unit Test Bootstrap ---
# We define the shared test library here so it is available to all unit test scripts
# without needing to distribute a separate file in the repo if we don't want to.
cat << 'EOF' > /tmp/test_lib.sh
#!/bin/bash
set -o errexit
set -o pipefail

# --- Test Environment Setup ---
setup_suite() {
    TEST_ROOT=$(mktemp -d)
    trap 'rm -rf "$TEST_ROOT"' EXIT

    # Standard Paths
    export HOME="$TEST_ROOT/home"
    export WORKSPACE="$TEST_ROOT/workspace"
    export STATE_DIR="$WORKSPACE/state"
    export LOG_FILE="$STATE_DIR/devcontainer-profile.log"
    export AUDIT_LOG="$TEST_ROOT/audit.log"
    
    # Engine Paths
    export MANAGED_CONFIG_DIR="$HOME/.devcontainer-profile"
    export USER_CONFIG_PATH="$MANAGED_CONFIG_DIR/config.json"
    export VOLUME_CONFIG_DIR="$STATE_DIR/configs"
    export USER_PATH_FILE="$HOME/.devcontainer.profile_path"
    export USER_ENV_FILE="$HOME/.devcontainer.profile_env"

    mkdir -p "$HOME" "$STATE_DIR" "$WORKSPACE/tmp" "$MANAGED_CONFIG_DIR" "$VOLUME_CONFIG_DIR"
    touch "$LOG_FILE" "$AUDIT_LOG"

    # Plugin Source Discovery (Handle CI vs Local paths)
    if [[ -d "/usr/local/share/devcontainer-profile/plugins" ]]; then
        REAL_PLUGIN_SRC="/usr/local/share/devcontainer-profile/plugins"
        REAL_SCRIPT_SRC="/usr/local/share/devcontainer-profile/scripts"
    elif [[ -d "./src/devcontainer-profile/scripts/plugins" ]]; then
        REAL_PLUGIN_SRC="./src/devcontainer-profile/scripts/plugins"
        REAL_SCRIPT_SRC="./src/devcontainer-profile/scripts"
    else
        # Fallback search
        REAL_PLUGIN_SRC=$(find / -type d -name "plugins" | grep "devcontainer-profile" | head -n 1)
        REAL_SCRIPT_SRC=$(dirname "$REAL_PLUGIN_SRC")
    fi

    # Copy plugins to test root to ensure hermetic execution
    export PLUGIN_DIR="$TEST_ROOT/plugins"
    export SCRIPT_DIR="$TEST_ROOT/scripts"
    mkdir -p "$PLUGIN_DIR" "$SCRIPT_DIR"
    cp -r "$REAL_PLUGIN_SRC/"* "$PLUGIN_DIR/"
    cp -r "$REAL_SCRIPT_SRC/"* "$SCRIPT_DIR/"
}

# --- Mocking Framework ---
setup_mocks() {
    MOCK_BIN="$TEST_ROOT/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"

    # Mocks that just log their arguments
    local tools=("apt-get" "pip" "npm" "go" "cargo" "code" "feature-installer")
    for tool in "${tools[@]}"; do
        mock_bin "$tool"
    done

    # Sudo Mock: Just executes the command but logs the attempt
    cat << MOCK > "$MOCK_BIN/sudo"
#!/bin/bash
echo "AUDIT: sudo \$*" >> "$AUDIT_LOG"
shift # remove 'sudo'
"\$@"
MOCK
    chmod +x "$MOCK_BIN/sudo"
}

mock_bin() {
    local name="$1"
    cat << MOCK > "$MOCK_BIN/$name"
#!/bin/bash
echo "AUDIT: $name \$*" >> "$AUDIT_LOG"
MOCK
    chmod +x "$MOCK_BIN/$name"
}

# --- Shared Utils Mock ---
# We mock the engine's internal logging functions to keep stdout clean
mock_utils() {
    log() { echo "[$1] $2" >> "$LOG_FILE"; }
    info() { log "INFO" "$1"; }
    warn() { log "WARN" "$1"; }
    error() { log "ERROR" "$1"; }
    ensure_root() { echo "AUDIT: sudo $*" >> "$AUDIT_LOG"; "$@"; }
    
    # Export for subshells
    export -f log info warn error ensure_root
}

# --- Assertions ---
assert_audit() {
    local expected="$1"
    if grep -Fq "$expected" "$AUDIT_LOG"; then
        echo -e "  \e[32m[PASS]\e[0m Audit contains: '$expected'"
    else
        echo -e "  \e[31m[FAIL]\e[0m Audit missing: '$expected'"
        echo "   >>> START AUDIT LOG <<<"
        cat "$AUDIT_LOG"
        echo "   >>> END AUDIT LOG <<<"
        exit 1
    fi
}

assert_file_exists() {
    if [[ -f "$1" || -L "$1" ]]; then
        echo -e "  \e[32m[PASS]\e[0m File exists: $1"
    else
        echo -e "  \e[31m[FAIL]\e[0m File missing: $1"
        exit 1
    fi
}

assert_eq() {
    if [[ "$1" == "$2" ]]; then
         echo -e "  \e[32m[PASS]\e[0m $3"
    else
         echo -e "  \e[31m[FAIL]\e[0m $3 (Expected '$1', got '$2')"
         exit 1
    fi
}
EOF

# --- 3. Execute Unit Suites ---
run_suite() {
    local script="$1"
    echo -e "\n>>> Running Suite: $script"
    # Run in a subshell so environments don't leak between suites
    ( bash "$script" ) || exit 1
}

# Execute
run_suite "./test_engine.sh"
run_suite "./test_parsing.sh"
run_suite "./test_plugins.sh"
run_suite "./test_xdg.sh"

reportResults