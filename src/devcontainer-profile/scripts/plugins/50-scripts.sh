#!/bin/bash
# 50-scripts.sh - Arbitrary user scripts
source "${LIB_PATH}"

run_scripts() {
    local script_count
    script_count=$(jq '.scripts // [] | length' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ "$script_count" == "0" ]] && return 0

    info "Scripts" "Executing $script_count user scripts..."

    local i=0
    while [[ $i -lt $script_count ]]; do
        local script_content
        script_content=$(jq -r ".scripts[$i]" "${USER_CONFIG_PATH}")
        
        info "Scripts" "Running script #$((i+1))"
        # Security: User provided scripts. We run them, but we trap errors.
        if ! ( eval "${script_content}" ); then
            warn "Scripts" "Script #$((i+1)) returned non-zero exit code."
        fi
        i=$((i+1))
    done
}

run_scripts