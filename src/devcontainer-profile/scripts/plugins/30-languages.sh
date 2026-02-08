#!/usr/bin/env bash

# Plugin: Languages
# Handles pip, npm, go, cargo

# Generic installer function
# $1: lang_key (e.g., "pip")
# $2: default_bin (e.g., "pip")
# $3: install_cmd_template (Use %BIN% and %PKG%)
install_lang() {
    local key="$1"
    local bin_name="$2"
    local cmd_tpl="$3"
    
    # 1. Parse Config
    local config
    config=$(jq -c ".\"$key\" // empty" "${USER_CONFIG_PATH}")
    [[ -z "$config" ]] && return

    local resolved_bin="$bin_name"
    local packages=""

    if echo "$config" | jq -e 'type == "array"' >/dev/null; then
        packages=$(echo "$config" | jq -r '.[] | select(type=="string")')
    elif echo "$config" | jq -e 'type == "object"' >/dev/null; then
        resolved_bin=$(echo "$config" | jq -r ".bin // \"$bin_name\"")
        packages=$(echo "$config" | jq -r '.packages[]?')
    fi

    [[ -z "$packages" ]] && return

    # 2. Find Binary
    local exec_path
    if ! exec_path=$(find_binary "$resolved_bin"); then
        warn "[$key] Binary '$resolved_bin' not found. Skipping."
        return
    fi

    info "[$key] Installing using $exec_path..."

    # 3. Install Loop
    while read -r pkg; do
        [[ -z "$pkg" ]] && continue
        
        # Replace placeholders
        local cmd="${cmd_tpl//%BIN%/$exec_path}"
        cmd="${cmd//%PKG%/$pkg}"
        
        # Execute (capture output to log)
        if ! eval "$cmd" >>"${LOG_FILE}" 2>&1; then
            warn "[$key] Failed to install $pkg"
        fi
    done <<< "$packages"
}

run_languages() {
    # PIP
    # Note: Modern pip requires break-system-packages or virtualenv. 
    # We try --break-system-packages only if supported.
    local pip_opts="install --user --upgrade"
    if python3 -m pip install --help 2>&1 | grep -q "break-system-packages"; then
        pip_opts="$pip_opts --break-system-packages"
    fi
    install_lang "pip" "pip" "%BIN% $pip_opts %PKG%"

    # NPM
    install_lang "npm" "npm" "%BIN% install -g %PKG%"

    # GO
    # Handle versioning (@latest) if missing
    install_lang "go" "go" "target='%PKG%'; if [[ \"\$target\" != *\"@\"* ]]; then target=\"\$target@latest\"; fi; %BIN% install \"\$target\""

    # CARGO
    install_lang "cargo" "cargo" "%BIN% install %PKG%"

    # GEM
    install_lang "gem" "gem" "%BIN% install --no-document %PKG%"
}

run_languages