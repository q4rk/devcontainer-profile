#!/bin/bash
# 30-languages.sh - Polyglot package manager support
source "${LIB_PATH}"

# Ensure we have common environments loaded
load_cargo_env() {
    [[ -f "/usr/local/cargo/env" ]] && . "/usr/local/cargo/env"
    [[ -f "${TARGET_HOME}/.cargo/env" ]] && . "${TARGET_HOME}/.cargo/env"
    # Ensure PATH is exported for subshells
    export PATH="${PATH}"
}
load_cargo_env

# Helper: Extract binary name, defaulting if necessary
get_tool_bin() {
    local key="$1"
    local default="$2"
    if [[ -f "${USER_CONFIG_PATH}" ]]; then
        jq -r ".[\"${key}\"] | if type==\"object\" then (.bin // \"${default}\") else \"${default}\" end" "${USER_CONFIG_PATH}" 2>/dev/null
    else
        echo "$default"
    fi
}

# Helper: Extract packages list
get_tool_pkgs() {
    local key="$1"
    if [[ -f "${USER_CONFIG_PATH}" ]]; then
        # Handle:
        # 1. Object: {"npm": {"packages": ["a"]}}
        # 2. Array:  {"npm": ["a", {"packages": ["b"]}]}
        # 3. String: {"npm": "a"} (fallback)
        jq -r ".[\"${key}\"] | 
            if type==\"object\" then 
                .packages[]? 
            elif type==\"array\" then 
                .[] | (if type==\"string\" then . else .packages[]? end)
            else 
                . 
            end" "${USER_CONFIG_PATH}" 2>/dev/null | grep -v "null"
    fi
}

# Helper to resolve binaries (returns absolute path)
resolve_binary() {
    local cmd="$1"
    local p
    p=$(command -v "$cmd" 2>/dev/null)
    if [[ -n "$p" ]]; then
        echo "$p"
        return 0
    fi
    
    local candidates=(
        "${TARGET_HOME}/.cargo/bin/${cmd}"
        "${TARGET_HOME}/go/bin/${cmd}"
        "${TARGET_HOME}/.local/bin/${cmd}"
        "/usr/local/go/bin/${cmd}"
        "/usr/local/cargo/bin/${cmd}"
        "/usr/local/bin/${cmd}"
        "/usr/games/${cmd}"
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
    packages=$(get_tool_pkgs "pip")
    [[ -z "$packages" ]] && return 0

    local raw_bin_name
    raw_bin_name=$(get_tool_bin "pip" "pip")
    local pip_bin
    pip_bin=$(resolve_binary "$raw_bin_name")
    
    # Fallback to pip3 if pip not found
    if [[ -z "$pip_bin" && "$raw_bin_name" == "pip" ]]; then
        pip_bin=$(resolve_binary "pip3")
        [[ -n "$pip_bin" ]] && raw_bin_name="pip3"
    fi
    
    if [[ -n "$pip_bin" ]]; then
        info "Pip" "Installing packages using '$raw_bin_name'..."
        local args=("install" "--user" "--upgrade")
        if "$pip_bin" install --help 2>&1 | grep -q "break-system-packages"; then
            args+=("--break-system-packages")
        fi
        mapfile -t pkg_array <<< "$packages"
        "$pip_bin" "${args[@]}" "${pkg_array[@]}" || warn "Pip" "Installation failed"
    else
        warn "Pip" "Binary '$raw_bin_name' not found. Skipping."
    fi
}

install_npm() {
    local packages
    packages=$(get_tool_pkgs "npm")
    [[ -z "$packages" ]] && return 0

    local raw_bin_name
    raw_bin_name=$(get_tool_bin "npm" "npm")
    local npm_bin
    npm_bin=$(resolve_binary "$raw_bin_name")

    if [[ -n "$npm_bin" ]]; then
        info "Npm" "Installing global packages using '$raw_bin_name'..."
        mapfile -t pkg_array <<< "$packages"
        
        # Try global install without sudo first (common for NVM/user nodes)
        if ! "$npm_bin" install -g "${pkg_array[@]}"; then
             # Fallback to root if needed
             ensure_root "$npm_bin" install -g "${pkg_array[@]}" || warn "Npm" "Installation failed"
        fi

        # Dynamically add npm global bin to PATH for current session
        local npm_prefix
        npm_prefix=$("$npm_bin" config get prefix 2>/dev/null)
        if [[ -d "${npm_prefix}/bin" ]]; then
            case ":$PATH:" in *":${npm_prefix}/bin:"*) ;; *) export PATH="$PATH:${npm_prefix}/bin" ;; esac
        fi
    else
        warn "Npm" "Binary '$raw_bin_name' not found. Skipping."
    fi
}

install_gem() {
    local packages; packages=$(get_tool_pkgs "gem")
    [[ -z "$packages" ]] && return 0

    local raw_bin_name; raw_bin_name=$(get_tool_bin "gem" "gem")
    local gem_bin; gem_bin=$(resolve_binary "$raw_bin_name")

    if [[ -n "$gem_bin" ]]; then
        info "Gem" "Installing packages using '$raw_bin_name'..."
        mapfile -t pkg_array <<< "$packages"
        
        # Try user-level install first
        if ! "$gem_bin" install --user-install --no-document "${pkg_array[@]}"; then
             ensure_root "$gem_bin" install --no-document "${pkg_array[@]}" || warn "Gem" "Installation failed"
        fi

        # Dynamically add the gem bin path to current PATH so subsequent plugins can use it
        local user_gem_bin
        user_gem_bin=$("$gem_bin" env user_gemhome 2>/dev/null)/bin
        if [[ -d "$user_gem_bin" ]]; then
            case ":$PATH:" in *":${user_gem_bin}:"*) ;; *) export PATH="$PATH:${user_gem_bin}" ;; esac
        fi
    else
        warn "Gem" "Binary '$raw_bin_name' not found. Skipping."
    fi
}

install_go() {
    local packages
    packages=$(get_tool_pkgs "go")
    [[ -z "$packages" ]] && return 0

    local raw_bin_name
    raw_bin_name=$(get_tool_bin "go" "go")
    local go_bin
    go_bin=$(resolve_binary "$raw_bin_name")

    if [[ -n "$go_bin" ]]; then
        info "Go" "Installing tools using '$raw_bin_name'..."
        while IFS= read -r pkg; do
             [[ -z "$pkg" ]] && continue
             [[ "$pkg" != *"@"* ]] && pkg="${pkg}@latest"
             "$go_bin" install "$pkg" || warn "Go" "Failed: $pkg"
        done <<< "$packages"
    else
        warn "Go" "Binary '$raw_bin_name' not found. Skipping."
    fi
}

install_cargo() {
    local packages
    packages=$(get_tool_pkgs "cargo")
    [[ -z "$packages" ]] && return 0
    
    load_cargo_env
    local raw_bin_name
    raw_bin_name=$(get_tool_bin "cargo" "cargo")
    local cargo_bin
    cargo_bin=$(resolve_binary "$raw_bin_name")

    if [[ -n "$cargo_bin" ]]; then
        info "Cargo" "Installing crates using '$raw_bin_name'..."
        
        if command -v rustup >/dev/null 2>&1; then
            if ! rustup default >/dev/null 2>&1; then
                info "Cargo" "Setting rustup default to stable..."
                rustup default stable || true
                cargo_bin=$(resolve_binary "$raw_bin_name")
            fi
        fi
        # Update registry index once
        "$cargo_bin" search --limit 1 verify-network >/dev/null 2>&1 || true

        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            "$cargo_bin" install "$pkg" || warn "Cargo" "Failed: $pkg"
        done <<< "$packages"
    else
        warn "Cargo" "Binary '$raw_bin_name' not found. Skipping."
    fi
}

install_pip
install_npm
install_gem
install_go
install_cargo
