#!/usr/bin/env bash

set -o nounset
set -o pipefail

readonly LIB_PATH_DEFAULT="/usr/local/share/devcontainer-profile/lib/utils.sh"
readonly LIB_PATH="${LIB_PATH:-$LIB_PATH_DEFAULT}"
source "${LIB_PATH}"

export WORKSPACE="${WORKSPACE:-/var/tmp/devcontainer-profile}"
export STATE_DIR="${STATE_DIR:-${WORKSPACE}/state}"

detect_user_context

readonly LOCK_FILE="${STATE_DIR}/engine.lock"
readonly HASH_FILE="${STATE_DIR}/last_applied_hash"
readonly INSTANCE_MARKER="${TARGET_HOME}/.devcontainer.profile.applied"
readonly LOG_FILE="${STATE_DIR}/profile.log"
readonly PLUGIN_DIR="${PLUGIN_DIR:-/usr/local/share/devcontainer-profile/plugins}"

initialize_workspace() {
    # Ensure dirs exists and has correct permissions
    if [[ ! -d "${STATE_DIR}" ]]; then
        ensure_root mkdir -p "${STATE_DIR}" "${WORKSPACE}/tmp"
        ensure_root chmod 1777 "${WORKSPACE}" "${STATE_DIR}" "${WORKSPACE}/tmp"
    fi

    if [[ ! -d "${VOLUME_CONFIG_DIR}" ]]; then
        ensure_root mkdir -p "${VOLUME_CONFIG_DIR}"
        safe_chown "${TARGET_USER}" "${VOLUME_CONFIG_DIR}"
    fi

    if [[ ! -f "${LOG_FILE}" ]]; then
        ensure_root touch "${LOG_FILE}"
        ensure_root chmod 0666 "${LOG_FILE}"
    fi
}

discover_configuration() {
    info "Core" "Scanning for configuration..."
    
    # If the volume already has a config, we trust it (it means the user edited it inside container)
    if [[ -f "${VOLUME_CONFIG_DIR}/config.json" ]]; then
        info "Core" "Using existing configuration from persistent volume."
        return 0
    fi

    local candidates=(
        "${WORKSPACE}/.config/.devcontainer.profile/config.json"
        "${WORKSPACE}/.config/.devcontainer.profile/devcontainer.profile.json"
        "${WORKSPACE}/.config/.devcontainer.profile/.devcontainer.profile"
        "/etc/user-host-config/devcontainer.profile/config.json"
        "${MANAGED_CONFIG_DIR}/config.json"
        "${MANAGED_CONFIG_DIR}/devcontainer.profile.json"
        "${MANAGED_CONFIG_DIR}/.devcontainer.profile"
        "${TARGET_HOME}/.config/devcontainer.profile/config.json"
        "${TARGET_HOME}/.config/devcontainer.profile/devcontainer.profile.json"
        "${TARGET_HOME}/.config/devcontainer.profile/.devcontainer.profile"
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
        safe_chown "${TARGET_USER}" "${VOLUME_CONFIG_DIR}/config.json"
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
    safe_chown "${TARGET_USER}" "${link_target}"
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
    export PROFILE_CONFIG_VALID="true"
    if ! jq empty "${USER_CONFIG_PATH}" >/dev/null 2>&1; then
        error "Core" "Invalid JSON in configuration file: ${USER_CONFIG_PATH}"
        export PROFILE_CONFIG_VALID="false"
        
        # Inject warning into shell rc files
        local warning_msg="
echo '(!) Dev Container Profile Warning: Invalid JSON in ${USER_CONFIG_PATH}'
echo '    Some settings may not be applied. Check the logs for details:'
echo '    ${LOG_FILE}'
"
        update_file_idempotent "${TARGET_HOME}/.bashrc" "PROFILE_WARNING" "${warning_msg}"
        update_file_idempotent "${TARGET_HOME}/.zshrc" "PROFILE_WARNING" "${warning_msg}"
    else
        # Clear warning if config is valid
        update_file_idempotent "${TARGET_HOME}/.bashrc" "PROFILE_WARNING" ""
        update_file_idempotent "${TARGET_HOME}/.zshrc" "PROFILE_WARNING" ""
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

acquire_process_lock() {
    local force_mode="${1:-false}"
    
    if ! exec 200<>"${LOCK_FILE}"; then
         error "Core" "Failed to open lock file: ${LOCK_FILE}"
         return 1
    fi

    if ! flock -n 200; then
        local locking_pid
        locking_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
        
        if [[ "$force_mode" == "true" ]]; then
            warn "Core" "Force mode: Lock held by PID '${locking_pid}'."
            if [[ -n "$locking_pid" ]] && kill -0 "$locking_pid" 2>/dev/null; then
                warn "Core" "Killing process ${locking_pid}..."
                kill "$locking_pid" 2>/dev/null || true
                sleep 1
                if kill -0 "$locking_pid" 2>/dev/null; then
                     kill -9 "$locking_pid" 2>/dev/null || true
                     sleep 1
                fi
            fi
        else
            warn "Core" "Waiting for lock (held by PID '${locking_pid}')..."
            warn "Core" "Use 'apply-profile --force' to override."
        fi

        if ! flock -w 30 200; then
            warn "Core" "Timeout waiting for lock."
            return 1
        fi
    fi
    echo "$$" > "${LOCK_FILE}"
    return 0
}

should_proceed_with_restore() {
    local check_flag="${1:-false}"
    
    if [[ "$check_flag" != "true" ]]; then
        return 0
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/../feature_config.sh"
    
    if [[ -f "$config_file" ]]; then
        local RESTOREONCREATE
        source "$config_file"
        
        if [[ "${RESTOREONCREATE:-true}" != "true" ]]; then
            info "Core" "Automatic restore disabled (restoreOnCreate=false). Skipping."
            return 1
        fi
        info "Core" "Automatic restore enabled. Proceeding..."
        return 0
    else
        warn "Core" "Feature config missing. Skipping automatic restore."
        return 1 
    fi
}

run_diagnostics() {
    info "Diagnostics" "User: ${TARGET_USER} (UID: $(id -u))"
    info "Diagnostics" "Home: ${TARGET_HOME}"
    info "Diagnostics" "Config: ${USER_CONFIG_PATH}"

    check_loc() {
        local cmd="$1"
        local loc
        loc=$(type -P "$cmd" 2>/dev/null || true)
        if [[ -n "$loc" ]]; then
            info "  > Binary '$cmd' found at: $loc"
        else
            info "  > Binary '$cmd' NOT in PATH"
        fi
    }

    info "[Diagnostics] Toolchain Probe:"
    check_loc "cargo"
    check_loc "rustup"
    check_loc "go"
    check_loc "pip"
    check_loc "npm"
    check_loc "gem"
    check_loc "python3"
    check_loc "node"


    check_tool() {
        if command -v "$1" >/dev/null 2>&1; then
            info "Diagnostics" "Found: $1 ($(command -v "$1"))"
        else
            info "Diagnostics" "Missing: $1"
        fi
    }

    check_tool jq
    check_tool curl
    check_tool git
    check_tool code
}

main() {
    initialize_workspace
    
    exec 2>>"${LOG_FILE}"

    local force_mode=false
    local check_restore_flag=false
    
    for arg in "$@"; do
        if [[ "$arg" == "--force" ]]; then
            force_mode=true
        elif [[ "$arg" == "--restore-if-enabled" ]]; then
            check_restore_flag=true
        fi
    done

    if ! should_proceed_with_restore "$check_restore_flag"; then
        return 0
    fi

    if ! acquire_process_lock "$force_mode"; then
        return 1
    fi

    discover_configuration
    link_managed_directory
    run_diagnostics

    if should_run; then
        info "Core" "Changes detected. Applying profile..."
        
        execute_plugins
        
        if [[ -f "${HASH_FILE}.new" ]]; then
            mv "${HASH_FILE}.new" "${HASH_FILE}"
        fi
        touch "${INSTANCE_MARKER}"
        safe_chown "${TARGET_USER}" "${INSTANCE_MARKER}"
        info "Core" "Profile applied successfully."
    else
        info "Core" "No changes detected. Skipping."
        
        # If config file is missing (deleted by user), ensure we don't have a stale warning
        if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
             update_file_idempotent "${TARGET_HOME}/.bashrc" "PROFILE_WARNING" ""
             update_file_idempotent "${TARGET_HOME}/.zshrc" "PROFILE_WARNING" ""
        fi
    fi

    rm -rf "${WORKSPACE}/tmp"/*
    if [[ -d "/var/lib/apt/lists" ]]; then
        ensure_root apt-get clean >/dev/null 2>&1 || true
    fi
}

main "$@"
