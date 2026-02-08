#!/usr/bin/env bash

# Plugin: APT
# Installs system packages

install_apt() {
    if ! command -v apt-get >/dev/null 2>&1; then return; fi

    # Extract packages, stripping 'null' and formatting version strings
    local packages
    packages=$(jq -r '.apt[]? | 
        if type == "string" then . 
        elif type == "object" and .version != "*" then .name + "=" + .version 
        else .name end' "${USER_CONFIG_PATH}")

    if [[ -z "$packages" ]]; then return; fi
    
    # Convert newline-separated string to array
    mapfile -t pkg_array <<< "$packages"
    if [[ ${#pkg_array[@]} -eq 0 ]]; then return; fi

    info "[APT] Installing ${#pkg_array[@]} packages..."

    # Cleanup yarn list if broken (Codespaces specific fix)
    if [[ -f /etc/apt/sources.list.d/yarn.list ]]; then
        ensure_root rm -f /etc/apt/sources.list.d/yarn.list
    fi

    export DEBIAN_FRONTEND=noninteractive
    
    # Run update only if we think we need it (simple heuristic: if last update > 24h, or on error)
    # For now, we update to be safe, but allow failure
    ensure_root apt-get update -y || warn "[APT] Update failed, trying installation anyway..."

    if ! ensure_root apt-get install -y --no-install-recommends "${pkg_array[@]}"; then
        warn "[APT] Install failed. Attempting 'fix-broken'..."
        ensure_root apt-get install --fix-broken -y
        # Retry once
        if ! ensure_root apt-get install -y --no-install-recommends "${pkg_array[@]}"; then
             error "[APT] Fatal error installing packages."
             return 1
        fi
    fi
}

install_apt