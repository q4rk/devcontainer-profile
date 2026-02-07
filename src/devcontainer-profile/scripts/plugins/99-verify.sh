#!/bin/bash

phase_verify() {
    local commands=()
    while IFS='' read -r line; do commands+=("$line"); done < <(
        jq -r '.verify[]? // empty' "${USER_CONFIG_PATH}"
    )

    [[ ${#commands[@]} -eq 0 ]] && return

    info "[Verify] Running health checks..."
    
    local passed=0
    local failed=0

    for cmd in "${commands[@]}"; do
        info "  > Verifying: $cmd"
        if ( eval "$cmd" ) >>"${LOG_FILE}" 2>&1; then
            passed=$((passed + 1))
        else
            warn "  > FAILED: $cmd"
            failed=$((failed + 1))
        fi
    done

    info "[Verify] Report: ${passed} passed, ${failed} failed."
    
    if [[ $failed -gt 0 ]]; then
        warn "Some personalization checks failed. Check the logs for details."
    fi
}

phase_verify
