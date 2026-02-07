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

# Check common Rust locations
rust_paths=("/usr/local/cargo/bin" "/usr/local/rustup/bin" "/home/codespace/.cargo/bin")
for p in "${rust_paths[@]}"; do
    if [[ -d "$p" ]]; then
        info "  > Directory exists: $p"
        ls -F "$p" | head -n 5 | sed 's/^/    - /' >> "${LOG_FILE}"
    fi
done
