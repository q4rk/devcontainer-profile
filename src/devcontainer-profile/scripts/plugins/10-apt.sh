#!/bin/bash
# 10-apt.sh - Install Debian packages
source "${LIB_PATH}"

run_apt() {
    # Extract packages, filtering out versions for now (simple implementation)
    # Complex versioning logic handled by jq
    local packages=()
    while IFS='' read -r line; do 
        [[ -n "$line" ]] && packages+=("$line")
    done < <(jq -r '.apt[]? | if type=="string" then . else .name + (if .version then "=\(.version)" else "" end) end' "${USER_CONFIG_PATH}" 2>/dev/null)

    [[ ${#packages[@]} -eq 0 ]] && return 0

    info "APT" "Installing: ${packages[*]}"

    # Clean yarn list if present (common Dev Container issue)
    if [[ -f /etc/apt/sources.list.d/yarn.list ]]; then
        ensure_root rm -f /etc/apt/sources.list.d/yarn.list
    fi

    # Update logic with error tolerance
    export DEBIAN_FRONTEND=noninteractive
    ensure_root apt-get update -y || warn "APT" "Update failed, attempting install anyway..."

    if ! ensure_root apt-get install -y --no-install-recommends "${packages[@]}"; then
        warn "APT" "Install failed. Attempting --fix-broken..."
        ensure_root apt-get install -f -y
        if ! ensure_root apt-get install -y --no-install-recommends "${packages[@]}"; then
             error "APT" "Failed to install packages."
             return 1
        fi
    fi
}

run_apt