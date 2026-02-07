#!/bin/bash

apt() {
    info "[APT] Checking packages..."
    # Apt doesn't like 'package=*', strip it if found.
    local packages=()
    while IFS='' read -r line; do packages+=("$line"); done < <(
        jq -r '.apt[]? |
            if type == "string" then
                .
            else
                if .version and .version != "*" then
                    .name + "=" + .version
                else
                    .name
                end
            end' "${USER_CONFIG_PATH}"
    )
    [[ ${#packages[@]} -eq 0 ]] && return

    # Fix for Yarn GPG error if it exists (common in Codespaces/Devcontainers)
    if [[ -f /etc/apt/sources.list.d/yarn.list ]]; then
        info "[APT] Cleaning up problematic Yarn repository..."
        ensure_root rm -f /etc/apt/sources.list.d/yarn.list
    fi

    info "[APT] Installing: ${packages[*]}"
    
    # We run update once but ignore errors. Some base images have broken third-party repos
    # that we don't depend on. 
    DEBIAN_FRONTEND=noninteractive ensure_root apt-get update -y || warn "[APT] apt-get update encountered errors. Attempting to proceed..."

    if ! DEBIAN_FRONTEND=noninteractive ensure_root apt-get install -y --no-install-recommends "${packages[@]}" >>"${LOG_FILE}" 2>&1; then
        warn "[APT] Primary installation failed. Attempting to fix and retry..."
        ensure_root apt-get install -f -y >>"${LOG_FILE}" 2>&1
        if ! DEBIAN_FRONTEND=noninteractive ensure_root apt-get install -y --no-install-recommends "${packages[@]}" >>"${LOG_FILE}" 2>&1; then
            error "[APT] Installation failed for ${packages[*]}. Check ${LOG_FILE}"
        fi
    fi
}

apt
