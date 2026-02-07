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

    info "[APT] Installing: ${packages[*]}"
    local retries=3
    local count=0
    until ensure_root apt-get update -q; do
        count=$((count + 1))
        [[ $count -lt $retries ]] || { error "[APT] Update failed."; return 1; }
        sleep 2
    done
    ensure_root apt-get install -y --no-install-recommends "${packages[@]}" >>"${LOG_FILE}" 2>&1
}

apt
