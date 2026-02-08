#!/usr/bin/env bash

#
# lib/utils.sh
# Shared functions for devcontainer-profile
#

export LOG_FILE="${LOG_FILE:-/var/tmp/devcontainer-profile/state/devcontainer-profile.log}"

# --- Logging ---
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%dT%H:%M:%S')
    
    # Emit to stderr (terminal) and log file
    echo "[${timestamp}] [${level}] ${msg}" | tee -a "${LOG_FILE}" >&2
}

info()  { log "INFO" "$@"; }
warn()  { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }

# --- Privileges ---
# Executes a command as root, preserving environment variables
ensure_root() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    else
        if command -v sudo >/dev/null 2>&1; then
            sudo -n -E -H "$@"
        else
            error "Root required but sudo not available."
            return 1
        fi
    fi
}

# --- File Operations ---
# Safely append text to a file if it doesn't already exist
# Usage: safe_append_if_missing "marker_string" "file_path" "content"
safe_append_if_missing() {
    local marker="$1"
    local file="$2"
    local content="$3"

    if [[ ! -f "$file" ]]; then return 0; fi

    if ! grep -Fq "$marker" "$file"; then
        echo -e "\n${content}" >> "$file"
        info "Updated $file with configuration."
    fi
}

# --- Configuration Parsing ---
# Extract a key from JSON, handling defaults
# Usage: get_config_value ".key" "default_value"
get_config_value() {
    local filter="$1"
    local default="$2"
    local result
    
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
        echo "$default"
        return
    fi

    result=$(jq -r "${filter} // empty" "${USER_CONFIG_PATH}" 2>/dev/null)
    echo "${result:-$default}"
}

# --- Tool Discovery ---
# Checks path and common locations for a binary
find_binary() {
    local cmd="$1"
    local existing
    
    existing=$(type -P "$cmd" 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
        echo "$existing"
        return 0
    fi

    # Common priority paths
    local paths=(
        "$HOME/.local/bin"
        "$HOME/go/bin"
        "$HOME/.cargo/bin"
        "/usr/local/bin"
        "/usr/local/go/bin"
        "/usr/local/cargo/bin"
    )

    for p in "${paths[@]}"; do
        if [[ -x "$p/$cmd" ]]; then
            echo "$p/$cmd"
            return 0
        fi
    done
    return 1
}