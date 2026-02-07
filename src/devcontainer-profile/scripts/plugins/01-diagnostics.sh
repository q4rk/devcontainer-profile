#!/bin/bash

# Diagnostics Plugin for Dev Container Profile
# Runs early to help troubleshoot path and toolchain issues

info "[Diagnostics] System Context:"
info "  > User: $(id -un) (UID: $(id -u))"
info "  > Home: $HOME"
info "  > PATH: $PATH"

check_loc() {
    local cmd="$1"
    local loc
    loc=$(type -P "$cmd" 2>/dev/null || true)
    if [[ -n "$loc" ]]; then
        info "  > Binary '$cmd' found at: $loc"
    else
        info "  > Binary '$cmd' NOT in PATH"
    fi
}

info "[Diagnostics] Toolchain Probe:"
check_loc "cargo"
check_loc "rustup"
check_loc "go"
check_loc "pip"
check_loc "npm"
check_loc "gem"
check_loc "python3"
check_loc "node"

# Check common toolchain locations
probe_paths=(
    "/usr/local/cargo/bin"
    "/usr/local/rustup/bin"
    "/usr/local/go/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/local/python/bin"
    "/usr/local/py-utils/bin"
    "/usr/local/share/nvm/current/bin"
    "/home/codespace/.cargo/bin"
    "/home/codespace/go/bin"
    "/home/codespace/.local/bin"
)
for p in "${probe_paths[@]}"; do
    if [[ -d "$p" ]]; then
        count=$(ls -1 "$p" 2>/dev/null | wc -l)
        info "  > Directory exists ($count files): $p"
        if [[ $count -gt 0 ]]; then
            ls -F "$p" | head -n 3 | sed 's/^/    - /' >> "${LOG_FILE}"
        fi
    fi
done
