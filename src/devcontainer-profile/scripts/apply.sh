#!/bin/bash
set -o nounset
set -o pipefail

# Determine the target user and home directory
export TARGET_USER="${_REMOTE_USER:-$(id -un)}"
export TARGET_HOME
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
export TARGET_HOME="${TARGET_HOME:-$HOME}"

export WORKSPACE="/var/tmp/devcontainer-profile"
export STATE_DIR="${WORKSPACE}/state"
export LOG_FILE="${STATE_DIR}/devcontainer-profile.log"
export LOCK_FILE="${STATE_DIR}/devcontainer-profile.lock"
export INSTANCE_MARKER="${TARGET_HOME}/.devcontainer-profile.applied"
export MANAGED_CONFIG_DIR="${TARGET_HOME}/.devcontainer-profile"
export VOLUME_CONFIG_DIR="${STATE_DIR}/configs"
export USER_CONFIG_PATH="${MANAGED_CONFIG_DIR}/config.json"
export USER_PATH_FILE="${TARGET_HOME}/.devcontainer.profile_path"
export CONFIG_MOUNT="${WORKSPACE}/.config/.devcontainer-profile"
export ALTERNATIVE_CONFIG_MOUNT="/etc/user-host-config/devcontainer-profile"
export PLUGIN_DIR="/usr/local/share/devcontainer-profile/plugins"

log() { echo "[$(date +'%Y-%m-%dT%H:%M:%S')] [$1] $2" | tee -a "${LOG_FILE}" >&2; }
info() { log "INFO" "$1"; }
warn() { log "WARN" "$1"; }
error() { log "ERROR" "$1"; }

ensure_root() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            # Use -E to preserve the environment (including TARGET_HOME)
            sudo -n -E "$@"
        else
            "$@"
        fi
    fi
}

acquire_lock() {
    ensure_root mkdir -p "${STATE_DIR}"
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        warn "Core: Waiting for lock (held by another process)..."
        if ! flock -w 30 200; then
            error "Core: Could not acquire lock after 30s. Exiting."
            return 1
        fi
    fi
}

init_workspace() {
    ensure_root mkdir -p "${STATE_DIR}" "${WORKSPACE}/tmp" "${VOLUME_CONFIG_DIR}" || return 1
    
    # Ensure ownership of the entire workspace for the target user
    ensure_root chown -R "${TARGET_USER}:${TARGET_USER}" "${WORKSPACE}" >/dev/null 2>&1 || true
    
    ensure_root chmod 1777 /tmp >/dev/null 2>&1 || true
    ensure_root chmod 1777 "${WORKSPACE}/tmp" >/dev/null 2>&1 || true
    
    # Ensure log file is writable by current user
    ensure_root touch "${LOG_FILE}" || return 1
    ensure_root chown "${TARGET_USER}:${TARGET_USER}" "${LOG_FILE}" >/dev/null 2>&1 || true
}

add_to_path() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$PATH:$dir"
    fi
}

reload_path() {
    # shellcheck source=/dev/null
    if [[ -f "${USER_PATH_FILE}" ]]; then source "${USER_PATH_FILE}"; fi
    local critical_paths=("/usr/games" "${TARGET_HOME}/.local/bin" "${TARGET_HOME}/go/bin" "${TARGET_HOME}/.cargo/bin" "/usr/local/cargo/bin" "/usr/local/go/bin")
    
    # Dynamic discovery of other bin dirs (e.g. /usr/local/python/bin, /usr/local/hugo/bin)
    while IFS= read -r dir; do
        critical_paths+=("$dir")
    done < <(find /usr/local /opt "${TARGET_HOME}" -maxdepth 4 -type d -name bin 2>/dev/null | grep -vE "^/usr/local/bin$|^/usr/bin$|^/bin$")

    for p in "${critical_paths[@]}"; do add_to_path "$p"; done
}

calculate_hash() {
    if [[ -f "${USER_CONFIG_PATH}" ]]; then
        md5sum "${USER_CONFIG_PATH}" | awk '{print $1}'
    else
        echo "none"
    fi
}

run_plugins() {
    if [[ -d "$PLUGIN_DIR" ]]; then
        reload_path
        # Export TARGET variables for plugins
        export HOME="${TARGET_HOME}"
        export USER="${TARGET_USER}"
        
        for script in $(find "$PLUGIN_DIR"/*.sh | sort); do
            if [[ -f "$script" ]]; then
                info "Running Plugin: $(basename "$script")"
                # shellcheck source=/dev/null
                ( set -o errexit; source "$script" ) >>"${LOG_FILE}" 2>&1 || warn "Plugin failed: $(basename "$script")"
                reload_path
            fi
        done
    else
        error "Core: Plugin directory missing."
    fi
}

main() {
    if ! init_workspace; then
        echo "(!) ERROR: Could not initialize workspace." >&2
        return 0
    fi

    if ! acquire_lock; then return 0; fi
    info "=== STARTING DEV CONTAINER PROFILE ENGINE (User: ${TARGET_USER}, Home: ${TARGET_HOME}) ==="

    if [[ -f "/usr/local/share/devcontainer-profile/defaults.env" ]]; then
        # shellcheck source=/dev/null
        source "/usr/local/share/devcontainer-profile/defaults.env"
    fi

    # Ingest if the volume is empty OR if config.json specifically is missing
    if [[ ! -f "${VOLUME_CONFIG_DIR}/config.json" ]]; then
        local config_source=""
        local discovery_dirs=(
            "${CONFIG_MOUNT}"
            "${ALTERNATIVE_CONFIG_MOUNT}"
        )
        info "Core: Searching for initial configuration..."
        for d in "${discovery_dirs[@]}"; do
            if [[ -f "${d}" ]]; then config_source="${d}"; break
            elif [[ -d "${d}" ]]; then
                for f in "config.json" "devcontainer.profile.json" ".devcontainer.profile" ".devcontainer-profile"; do
                    if [[ -f "${d}/${f}" ]]; then config_source="${d}/${f}"; break 2; fi
                done
            fi
        done
        
        # Check TARGET_HOME-based discovery files if mount-based discovery failed
        if [[ -z "$config_source" ]]; then
            for f in ".devcontainer.profile" ".devcontainer-profile" "config.json" "devcontainer.profile.json"; do
                if [[ -f "${TARGET_HOME}/${f}" ]] && [[ ! -L "${TARGET_HOME}/${f}" ]]; then
                    config_source="${TARGET_HOME}/${f}"
                    break
                fi
            done
        fi

        if [[ -n "$config_source" ]]; then
            info "Core: Ingesting initial config to volume: ${config_source}"
            cp -L "$config_source" "${VOLUME_CONFIG_DIR}/config.json" || true
            chown "${TARGET_USER}:${TARGET_USER}" "${VOLUME_CONFIG_DIR}/config.json" || true
        fi
    fi

    if [[ -e "${MANAGED_CONFIG_DIR}" ]] && [[ ! -L "${MANAGED_CONFIG_DIR}" ]]; then
        mv "${MANAGED_CONFIG_DIR}" "${MANAGED_CONFIG_DIR}.bak_$(date +%s)" || true
    fi
    rm -rf "${MANAGED_CONFIG_DIR}"
    ln -sf "${VOLUME_CONFIG_DIR}" "${MANAGED_CONFIG_DIR}"
    chown -h "${TARGET_USER}:${TARGET_USER}" "${MANAGED_CONFIG_DIR}" || true
    info "Core: Link established: ${MANAGED_CONFIG_DIR} -> ${VOLUME_CONFIG_DIR}"

    # If no config exists in the volume, stop here.
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
        info "Core: No configuration file found (${USER_CONFIG_PATH}). Skipping personalization."
        # We still touch the marker so we don't keep searching every single terminal open
        touch "${INSTANCE_MARKER}"
        chown "${TARGET_USER}:${TARGET_USER}" "${INSTANCE_MARKER}" || true
        return 0
    fi

    local current_hash
    current_hash=$(calculate_hash)
    local last_hash=""
    if [[ -f "${STATE_DIR}/last_applied_hash" ]]; then
        last_hash=$(cat "${STATE_DIR}/last_applied_hash")
    fi
    if [[ "${current_hash}" == "${last_hash}" ]] && [[ -f "${INSTANCE_MARKER}" ]]; then
        info "Core: Config unchanged and instance active. Skipping."
        return 0
    fi

    run_plugins
    echo "${current_hash}" > "${STATE_DIR}/last_applied_hash"
    touch "${INSTANCE_MARKER}"
    chown "${TARGET_USER}:${TARGET_USER}" "${STATE_DIR}/last_applied_hash" "${INSTANCE_MARKER}" || true
    info "=== COMPLETED ==="
}

main "$@" || true
exit 0
