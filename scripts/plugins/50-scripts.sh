#!/bin/bash

scripts() {
    local script_count
    script_count=$(jq '.scripts // [] | length' "${USER_CONFIG_PATH}")
    [[ "$script_count" == "0" ]] && return

    info "[Scripts] Executing user scripts..."

    local i=0
    while [[ $i -lt $script_count ]]; do
        local script_content
        script_content=$(jq -r ".scripts[$i]" "${USER_CONFIG_PATH}")
        info "  > Script #$((i+1))"
        if ! (eval "${script_content}") >>"${LOG_FILE}" 2>&1; then warn "Script #$((i+1)) failed."; fi
        i=$((i+1))
    done
}

scripts
