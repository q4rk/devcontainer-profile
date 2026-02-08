#!/usr/bin/env bash

# Plugin: Diagnostics
# Checks environment health

log_diag() {
    # Only verify major tools
    local tools=("cargo" "go" "pip" "npm" "node" "python3")
    local found=0
    
    for t in "${tools[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            found=$((found + 1))
        fi
    done
    
    info "[Diagnostics] Detected $found/${#tools[@]} core tools in PATH."
    info "[Diagnostics] PATH length: ${#PATH}"
}

log_diag