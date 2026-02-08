#!/bin/bash
# 30-languages.sh - Polyglot package manager support
source "${LIB_PATH}"

# Helper to resolve binaries (Check PATH, then common locations)
resolve_binary() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd"
        return 0
    fi
    
    # Check specific high-probability locations only (Optimization)
    local candidates=(
        "${TARGET_HOME}/.cargo/bin/${cmd}"
        "${TARGET_HOME}/go/bin/${cmd}"
        "/usr/local/go/bin/${cmd}"
        "/usr/local/bin/${cmd}"
    )
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

install_pip() {
    local packages
    packages=$(get_config_keys "pip")
    [[ -z "$packages" ]] && return 0

    local pip_bin
    pip_bin=$(resolve_binary "pip" || resolve_binary "pip3")
    
    if [[ -n "$pip_bin" ]]; then
        info "Pip" "Installing packages..."
        local args=("install" "--user" "--upgrade")
        
        # Check for PEP 668 compliance
        if "$pip_bin" install --help 2>&1 | grep -q "break-system-packages"; then
            args+=("--break-system-packages")
        fi
        
        # Convert newline separated string to array
        mapfile -t pkg_array <<< "$packages"
        "$pip_bin" "${args[@]}" "${pkg_array[@]}" || error "Pip" "Installation failed"
    else
        warn "Pip" "Binary not found. Skipping."
    fi
}

install_npm() {
    local packages
    packages=$(get_config_keys "npm")
    [[ -z "$packages" ]] && return 0

    local npm_bin
    npm_bin=$(resolve_binary "npm")

    if [[ -n "$npm_bin" ]]; then
        info "Npm" "Installing global packages..."
        mapfile -t pkg_array <<< "$packages"
        "$npm_bin" install -g "${pkg_array[@]}" || error "Npm" "Installation failed"
    else
        warn "Npm" "Binary not found. Skipping."
    fi
}

install_go() {
    local packages
    packages=$(get_config_keys "go")
    [[ -z "$packages" ]] && return 0

    local go_bin
    go_bin=$(resolve_binary "go")

    if [[ -n "$go_bin" ]]; then
        info "Go" "Installing tools..."
        while IFS= read -r pkg; do
             [[ -z "$pkg" ]] && continue
             [[ "$pkg" != *"@"* ]] && pkg="${pkg}@latest"
             "$go_bin" install "$pkg" || error "Go" "Failed: $pkg"
        done <<< "$packages"
    else
        warn "Go" "Binary not found. Skipping."
    fi
}

install_cargo() {
    local packages
    packages=$(get_config_keys "cargo")
    [[ -z "$packages" ]] && return 0
    
    local cargo_bin
    cargo_bin=$(resolve_binary "cargo")

    if [[ -n "$cargo_bin" ]]; then
        info "Cargo" "Installing crates..."
        # Ensure registry is updated only once
        "$cargo_bin" search --limit 1 verify-network >/dev/null 2>&1 || true

        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            "$cargo_bin" install "$pkg" || error "Cargo" "Failed: $pkg"
        done <<< "$packages"
    else
        warn "Cargo" "Binary not found. Skipping."
    fi
}

install_pip
install_npm
install_go
install_cargo