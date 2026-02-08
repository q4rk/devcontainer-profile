#!/usr/bin/env bash

#
# apply.sh
# Core orchestration engine for devcontainer-profile
#

set -o nounset
set -o pipefail
# We don't use 'set -e' globally here because we want to capture plugin failures 
# and log them without crashing the entire orchestration.

# --- Environment Setup ---
export TARGET_USER="${_REMOTE_USER:-$(id -un)}"
export TARGET_HOME
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
export TARGET_HOME="${TARGET_HOME:-$HOME}"

# Core Paths
export WORKSPACE="/var/tmp/devcontainer-profile"
export STATE_DIR="${WORKSPACE}/state"
export LOCK_FILE="${STATE_DIR}/devcontainer-profile.lock"
export INSTANCE_MARKER="${TARGET_HOME}/.devcontainer-profile.applied"
export MANAGED_CONFIG_DIR="${TARGET_HOME}/.devcontainer-profile"
export USER_CONFIG_PATH="${MANAGED_CONFIG_DIR}/config.json"
export PLUGIN_DIR="/usr/local/share/devcontainer-profile/plugins"
export LIB_DIR="/usr/local/share/devcontainer-profile/lib"

# Load Library
# shellcheck source=./lib/utils.sh
if [[ -f "${LIB_DIR}/utils.sh" ]]; then
    source "${LIB_DIR}/utils.sh"
else
    # Fallback for local testing
    source "$(dirname "$0")/../lib/utils.sh"
fi

# --- Core Functions ---

setup_workspace() {
    ensure_root mkdir -p "${STATE_DIR}" "${WORKSPACE}/tmp" "${WORKSPACE}/configs"
    ensure_root chown -R "${TARGET_USER}:${TARGET_USER}" "${WORKSPACE}"
    ensure_root chmod 1777 "${WORKSPACE}/tmp"
    
    if [[ ! -f "${LOG_FILE}" ]]; then
        ensure_root touch "${LOG_FILE}"
        ensure_root chown "${TARGET_USER}:${TARGET_USER}" "${LOG_FILE}"
    fi
}

acquire_lock() {
    # File Descriptor 200 used for locking
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        warn "Core: Waiting for lock..."
        if ! flock -w 30 200; then
            error "Core: Timeout waiting for lock. Exiting."
            exit 1
        fi
    fi
}

discover_configuration() {
    # If config is already active in volume, we rely on it.
    # Otherwise, we ingest from host mounts or home dir.
    if [[ -f "${WORKSPACE}/configs/config.json" ]]; then return; fi

    local candidates=(
        "${WORKSPACE}/.config/.devcontainer-profile/config.json"
        "${WORKSPACE}/.config/.devcontainer-profile/devcontainer.profile.json"
        "${TARGET_HOME}/.devcontainer.profile"
        "${TARGET_HOME}/config.json"
    )

    info "Core: Discovering configuration..."
    
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            info "Core: Found configuration at $c"
            cp "$c" "${WORKSPACE}/configs/config.json"
            return
        fi
    done
}

link_configuration() {
    # Create the "Solid Link"
    # We use a temp link and atomic move to ensure robustness
    local link_target="${WORKSPACE}/configs"
    local link_name="${MANAGED_CONFIG_DIR}"
    
    if [[ "$(readlink -f "${link_name}" 2>/dev/null)" != "${link_target}" ]]; then
        rm -rf "${link_name}"
        ln -sfn "${link_target}" "${link_name}"
        info "Core: Linked ${link_name} -> ${link_target}"
    fi
}

check_state_hash() {
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
        info "Core: No config found. Skipping."
        return 0 # Clean exit
    fi

    local current_hash
    current_hash=$(md5sum "${USER_CONFIG_PATH}" | awk '{print $1}')
    local last_hash=""
    
    if [[ -f "${STATE_DIR}/last_applied_hash" ]]; then
        last_hash=$(cat "${STATE_DIR}/last_applied_hash")
    fi

    if [[ "${current_hash}" == "${last_hash}" ]] && [[ -f "${INSTANCE_MARKER}" ]]; then
        info "Core: Configuration unchanged. Skipping."
        return 0
    fi

    # Return 1 to indicate "Proceed with apply"
    echo "${current_hash}" > "${STATE_DIR}/current_run_hash"
    return 1
}

run_plugins() {
    if [[ ! -d "$PLUGIN_DIR" ]]; then return; fi
    
    info "Core: Running plugins..."
    
    # Use nullglob to handle empty directory safely
    shopt -s nullglob
    for script in "$PLUGIN_DIR"/*.sh; do
        local script_name
        script_name=$(basename "$script")
        
        info ">>> Plugin: ${script_name}"
        
        # Run in subshell with strict error handling, but don't kill main loop
        (
            set -o errexit
            # shellcheck source=/dev/null
            source "$script"
        ) || error "Plugin ${script_name} failed."
        
    done
    shopt -u nullglob
}

finalize() {
    local hash_file="${STATE_DIR}/current_run_hash"
    if [[ -f "$hash_file" ]]; then
        mv "$hash_file" "${STATE_DIR}/last_applied_hash"
    fi
    touch "${INSTANCE_MARKER}"
}

# --- Main Execution ---

main() {
    setup_workspace
    acquire_lock
    
    # Trap for lock release isn't strictly necessary with flock on FD 
    # as the OS closes FDs on exit, releasing the lock.
    
    discover_configuration
    link_configuration
    
    if check_state_hash; then
        exit 0
    fi

    info "=== STARTING PROFILE APPLICATION (User: $TARGET_USER) ==="
    run_plugins
    finalize
    info "=== COMPLETED ==="
}

main "$@"