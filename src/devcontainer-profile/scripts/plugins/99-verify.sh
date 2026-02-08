#!/usr/bin/env bash

# Plugin: Verify
# Runs health checks

run_verification() {
    local checks
    checks=$(jq -r '.verify[]? // empty' "${USER_CONFIG_PATH}")
    [[ -z "$checks" ]] && return

    info "[Verify] Running health checks..."
    
    local failed=0
    while read -r cmd; do
        info " > Checking: $cmd"
        if ! eval "$cmd" >>"${LOG_FILE}" 2>&1; then
            error "Check failed: $cmd"
            failed=$((failed + 1))
        fi
    done <<< "$checks"

    if [[ $failed -gt 0 ]]; then
        warn "$failed checks failed. See ${LOG_FILE} for details."
    else
        info "All checks passed."
    fi
}

run_verification