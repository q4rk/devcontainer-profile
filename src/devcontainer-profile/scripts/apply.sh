#!/bin/bash
# Core Entrypoint for .devcontainer.profile
set -o nounset
set -o pipefail

# --- Bootstrap Environment ---
# Source the shared library. If missing, we cannot proceed.
readonly LIB_PATH_DEFAULT="/usr/local/share/devcontainer-profile/lib/utils.sh"
readonly LIB_PATH="${LIB_PATH:-$LIB_PATH_DEFAULT}"

if [[ ! -f "${LIB_PATH}" ]]; then
    local_file="$(dirname "$0")/../lib/utils.sh"
    if [[ -f $local_file ]]; then
        source "$local_file"
    else
        echo "(!) FATAL: Library not found at ${LIB_PATH}. Skipping." >&2
        exit 1
    fi   
else 
    source "${LIB_PATH}"
fi

# --- Global Constants ---
export WORKSPACE="${WORKSPACE:-/var/tmp/devcontainer-profile}"
export STATE_DIR="${STATE_DIR:-${WORKSPACE}/state}"

# Initialize Environment Variables
detect_user_context

readonly LOCK_FILE="${STATE_DIR}/engine.lock"
readonly HASH_FILE="${STATE_DIR}/last_applied_hash"
readonly INSTANCE_MARKER="${TARGET_HOME}/.devcontainer-profile.applied"
readonly LOG_FILE="${STATE_DIR}/profile.log"
readonly PLUGIN_DIR="${PLUGIN_DIR:-/usr/local/share/devcontainer-profile/plugins}"

# --- Main Execution Flow ---

initialize_workspace() {
    # Ensure workspace exists and has correct permissions
    if [[ ! -d "${STATE_DIR}" ]]; then
        ensure_root mkdir -p "${STATE_DIR}" "${WORKSPACE}/tmp"
        ensure_root chmod 1777 "${WORKSPACE}" "${STATE_DIR}" "${WORKSPACE}/tmp"
    fi
    
    # Ensure log file exists and is writable
    if [[ ! -f "${LOG_FILE}" ]]; then
        ensure_root touch "${LOG_FILE}"
        ensure_root chmod 0666 "${LOG_FILE}"
    fi
}

discover_configuration() {
    info "Core" "Scanning for configuration..."
    
    # 1. Check Volume (Persistence)
    # If the volume already has a config, we trust it (it means the user edited it inside container)
    if [[ -f "${VOLUME_CONFIG_DIR}/config.json" ]]; then
        info "Core" "Using existing configuration from persistent volume."
        return 0
    fi

    # 2. Check Host Mounts (Discovery)
    local candidates=(
        "${WORKSPACE}/.config/.devcontainer-profile/config.json"
        "${WORKSPACE}/.config/.devcontainer-profile/devcontainer.profile.json"
        "${WORKSPACE}/.config/.devcontainer-profile/.devcontainer.profile"
        "/etc/user-host-config/devcontainer-profile/config.json"
        "${MANAGED_CONFIG_DIR}/config.json"
        "${MANAGED_CONFIG_DIR}/devcontainer.profile.json"
        "${MANAGED_CONFIG_DIR}/.devcontainer.profile"
        "${TARGET_HOME}/.config/devcontainer-profile/config.json"
        "${TARGET_HOME}/.config/devcontainer-profile/devcontainer.profile.json"
        "${TARGET_HOME}/.config/devcontainer-profile/.devcontainer.profile"
    )

    local found_config=""
    for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
            found_config="$c"
            break
        fi
    done

    if [[ -n "$found_config" ]]; then
        info "Core" "Ingesting configuration: ${found_config}"
        ensure_root mkdir -p "${VOLUME_CONFIG_DIR}"
        ensure_root cp -L "${found_config}" "${VOLUME_CONFIG_DIR}/config.json"
        ensure_root chown "${TARGET_USER}:$(id -gn "${TARGET_USER}")" "${VOLUME_CONFIG_DIR}/config.json"
    else
        info "Core" "No configuration found. Engine will stand by."
        return 1
    fi
}

link_managed_directory() {
    # Establish ~/.devcontainer-profile -> /var/tmp/.../configs
    # This enables persistence across rebuilds
    local link_target="${MANAGED_CONFIG_DIR}"
    
    if [[ -L "${link_target}" ]]; then
        local current_dest
        current_dest=$(readlink -f "${link_target}")
        if [[ "${current_dest}" == "${VOLUME_CONFIG_DIR}" ]]; then
            return 0 # Already linked correctly
        fi
    fi
    
    # Backup if it's a real directory
    if [[ -d "${link_target}" && ! -L "${link_target}" ]]; then
        warn "Core" "Backing up existing directory at ${link_target}"
        mv "${link_target}" "${link_target}.bak.$(date +%s)"
    fi

    rm -rf "${link_target}"
    ln -s "${VOLUME_CONFIG_DIR}" "${link_target}"
    # chown might fail if user doesn't exist in unit tests, so we fail soft
    chown -h "${TARGET_USER}:$(id -gn "${TARGET_USER}")" "${link_target}" 2>/dev/null || true
    info "Core" "Linked ${link_target} -> ${VOLUME_CONFIG_DIR}"
}

should_run() {
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then return 1; fi

    local current_hash
    current_hash=$(md5sum "${USER_CONFIG_PATH}" | awk '{print $1}')
    
    local last_hash=""
    if [[ -f "${HASH_FILE}" ]]; then
        last_hash=$(cat "${HASH_FILE}")
    fi

    # Run if: Hash changed OR Instance marker missing (new container)
    if [[ "${current_hash}" != "${last_hash}" ]] || [[ ! -f "${INSTANCE_MARKER}" ]]; then
        echo "${current_hash}" > "${HASH_FILE}.new" # Store temp
        return 0
    fi

    return 1
}

execute_plugins() {
    if ! jq empty "${USER_CONFIG_PATH}" >/dev/null 2>&1; then
        error "Core" "Invalid JSON in configuration file: ${USER_CONFIG_PATH}"
        return 1
    fi
    info "Core" "Starting plugin execution sequence..."
    
    # Reload path to ensure we see tools installed by previous steps
    reload_path

    for script in "${PLUGIN_DIR}"/*.sh; do
        [[ -f "$script" ]] || continue
        
        local script_name
        script_name=$(basename "$script")
        
        info "Plugin" "Running ${script_name}..."
        
        # Execute in subshell to isolate environment changes, but trap errors
        if ( source "$script" ); then
            info "Plugin" "${script_name} completed."
        else
            error "Plugin" "${script_name} FAILED. Continuing soft..."
        fi
        
        # Re-source path after every plugin in case of new binaries
        reload_path
    done
}

main() {
    initialize_workspace
    
    # Redirect stderr to log file for the rest of the execution
    # This ensures the directory exists before we try to open the log file
    exec 2>>"${LOG_FILE}"

    # Acquire lock to prevent race conditions
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        warn "Core" "Waiting for lock..."
        if ! flock -w 30 200; then
            error "Core" "Timeout waiting for lock."
            return 0
        fi
    fi

    # 1. Setup Persistence Links
    discover_configuration
    link_managed_directory

    # 2. Check State
    if should_run; then
        info "Core" "Changes detected. Applying profile..."
        
        execute_plugins
        
        # Finalize
        if [[ -f "${HASH_FILE}.new" ]]; then
            mv "${HASH_FILE}.new" "${HASH_FILE}"
        fi
        touch "${INSTANCE_MARKER}"
        ensure_root chown "${TARGET_USER}:$(id -gn "${TARGET_USER}")" "${INSTANCE_MARKER}"
        info "Core" "Profile applied successfully."
    else
        info "Core" "No changes detected. Skipping."
    fi
}

# Run main
main "$@"
