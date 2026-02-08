#!/bin/bash
# 99-verify.sh
source "${LIB_PATH}"

run_verify() {
    local commands
    commands=$(get_config_keys "verify")
    [[ -z "$commands" ]] && return 0

    info "Verify" "Running verification checks..."
    local failed=0
    
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        if ( eval "$cmd" ) >/dev/null 2>&1; then
            info "Verify" "[PASS] $cmd"
        else
            error "Verify" "[FAIL] $cmd"
            failed=1
        fi
    done <<< "$commands"

    if [[ $failed -eq 1 ]]; then
        warn "Verify" "Some checks failed. See log for details."
    fi
}

run_verify