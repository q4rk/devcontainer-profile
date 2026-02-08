#!/bin/bash
# Shared Utility Library for Dev Container Profile

# --- Logging ---
log() {
    local level="${1:-INFO}"
    local category="${2:-General}"
    local message="${3:-}"
    
    # Handle case where only 2 args are passed (Level + Message)
    if [[ -z "$message" ]]; then
        message="$category"
        category="General"
    fi

    local timestamp
    timestamp=$(date +'%Y-%m-%dT%H:%M:%S')
    local msg="[${timestamp}] [${level}] [${category}] ${message}"
    echo "${msg}"
    # Mirror to log file if it exists and is writable
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Ensure directory exists (cheap check)
        if [[ -d "$(dirname "${LOG_FILE}")" ]]; then
            echo "${msg}" >> "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

info() { log "INFO" "$1" "${2:-}"; }
warn() { log "WARN" "$1" "${2:-}"; }
error() { log "ERROR" "$1" "${2:-}" >&2; }

# --- User & Context ---
detect_user_context() {
    export TARGET_USER="${TARGET_USER:-${_REMOTE_USER:-$(id -un)}}"
    
    if [[ -z "${TARGET_HOME:-}" ]]; then
        local user_home
        user_home=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
        export TARGET_HOME="${user_home:-$HOME}"
    else
        export TARGET_HOME
    fi
    
    # Managed paths
    export MANAGED_CONFIG_DIR="${TARGET_HOME}/.devcontainer.profile"
    export VOLUME_CONFIG_DIR="${STATE_DIR}/configs"
    export USER_CONFIG_PATH="${VOLUME_CONFIG_DIR}/config.json"
}

# --- System ---
ensure_root() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            # -n: non-interactive
            # We avoid -E to prevent HOME mismatch errors (e.g. rustup)
            sudo -n "$@"
        else
            warn "System" "sudo not available and not root. Command may fail: $*"
            "$@"
        fi
    fi
}

reload_path() {
    local path_file="${TARGET_HOME}/.devcontainer.profile_path"
    if [[ -f "${path_file}" ]]; then
        # shellcheck source=/dev/null
        source "${path_file}"
    fi

    local common_paths=(
        "/usr/games"
        "${TARGET_HOME}/.local/bin"
        "${TARGET_HOME}/go/bin"
        "${TARGET_HOME}/.cargo/bin"
        "${TARGET_HOME}/python/bin"
        "/usr/local/go/bin"
        "/usr/local/cargo/bin"
        "/usr/local/rustup/bin"
        "/usr/local/python/bin"
        "/usr/local/share/nvm/current/bin"
    )
    
    for p in "${common_paths[@]}"; do
        if [[ -d "$p" ]] && [[ ":$PATH:" != *":$p:"* ]]; then
            export PATH="$p:$PATH"
        fi
    done
}

# --- Config Parsing ---
get_config_keys() {
    local key="$1"
    if [[ -f "${USER_CONFIG_PATH}" ]]; then
        jq -r ".[\"${key}\"][]? // empty" "${USER_CONFIG_PATH}" 2>/dev/null
    fi
}

get_config_val() {
    local key="$1"
    local default="$2"
    if [[ -f "${USER_CONFIG_PATH}" ]]; then
        jq -r ".[\"${key}\"] // \"${default}\"" "${USER_CONFIG_PATH}" 2>/dev/null
    else
        echo "$default"
    fi
}

# --- File Operations ---
update_file_idempotent() {
    local file="$1"
    local block_name="$2"
    local content="$3"
    
    local start_marker="# START: ${block_name} (devcontainer-profile)"
    local end_marker="# END: ${block_name}"
    
    if [[ ! -f "$file" ]]; then touch "$file"; fi

    local tmp_file
    tmp_file=$(mktemp)

    if grep -qF "${start_marker}" "$file"; then
        awk -v start="${start_marker}" -v end="${end_marker}" '
            $0 == start { printing=0; next }
            $0 == end { printing=1; next }
            printing { print }
            BEGIN { printing=1 }
        ' "$file" > "$tmp_file"
    else
        cat "$file" > "$tmp_file"
    fi

    {
        echo ""
        echo "${start_marker}"
        echo "${content}"
        echo "${end_marker}"
    } >> "$tmp_file"

    cat "$tmp_file" > "$file"
    rm -f "$tmp_file"
}