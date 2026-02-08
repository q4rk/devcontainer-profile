#!/bin/bash

# Helper to safely resolve packages regardless of config format
resolve_configuration() {
    local key="$1"
    local default_bin="$2"

    RESOLVED_BIN=""
    RESOLVED_PKGS=""

    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
        return 0
    fi

    local raw_config
    raw_config=$(jq -c ".\"$key\" // empty" "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ -z "$raw_config" ]] && return 0

    local config_type
    config_type=$(echo "$raw_config" | jq -r 'type')

    if [[ "$config_type" == "object" ]]; then
        RESOLVED_BIN=$(echo "$raw_config" | jq -r ".bin // \"$default_bin\"")
        RESOLVED_PKGS=$(echo "$raw_config" | jq -r ".packages[]? // empty")

    elif [[ "$config_type" == "array" ]]; then
        RESOLVED_BIN="$default_bin"
        # Extract both top-level strings and strings from nested objects
        RESOLVED_PKGS=$(echo "$raw_config" | jq -r '
            .[] | 
            if type == "string" then 
                . 
            elif type == "object" then 
                .packages[]? // empty
            else 
                empty 
            end')
    fi
    
    if [[ -n "$RESOLVED_PKGS" ]]; then
        info "  [$key] Resolved: bin=$RESOLVED_BIN, pkgs=$(echo "$RESOLVED_PKGS" | wc -l) lines"
    fi
}

# Helper to find a binary if not in PATH
discover_binary() {
    local cmd="$1"
    DISCOVERED_BIN=""
    
    # 1. Check if already in PATH
    DISCOVERED_BIN=$(type -P "$cmd" 2>/dev/null || true)
    if [[ -n "$DISCOVERED_BIN" ]]; then
        return 0 
    fi

    # 2. Check Priority Locations
    local priority_paths=(
        "${HOME}/.cargo/bin"
        "${HOME}/go/bin"
        "${HOME}/.local/bin"
        "/usr/local/cargo/bin"
        "/usr/local/rustup/bin"
        "/usr/local/go/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/usr/games"
        "/home/linuxbrew/.linuxbrew/bin"
        "/opt/homebrew/bin"
    )
    for p in "${priority_paths[@]}"; do
        if [[ -x "$p/$cmd" ]]; then
            DISCOVERED_BIN="$p/$cmd"
            export PATH="$p:$PATH"
            return 0
        fi
    done

    # 3. Special Fallback for Rustup
    if [[ "$cmd" == "cargo" ]]; then
        local r_bin=""
        if command -v rustup >/dev/null 2>&1; then r_bin=$(command -v rustup);
        elif [[ -x "/usr/local/rustup/bin/rustup" ]]; then r_bin="/usr/local/rustup/bin/rustup";
        elif [[ -x "/usr/local/cargo/bin/rustup" ]]; then r_bin="/usr/local/cargo/bin/rustup";
        elif [[ -x "${HOME}/.cargo/bin/rustup" ]]; then r_bin="${HOME}/.cargo/bin/rustup"; fi
        
        if [[ -n "$r_bin" ]]; then
            local r_cargo
            r_cargo=$($r_bin which cargo 2>/dev/null || true)
            
            # If rustup which cargo failed, maybe no default toolchain?
            if [[ -z "$r_cargo" ]]; then
                # Attempt to set default stable if none exists
                $r_bin default stable >/dev/null 2>&1 || true
                r_cargo=$($r_bin which cargo 2>/dev/null || true)
            fi

            if [[ -n "$r_cargo" ]] && [[ -x "$r_cargo" ]]; then
                DISCOVERED_BIN="$r_cargo"
                export PATH="$(dirname "$r_cargo"):$PATH"
                return 0
            fi
        fi
    fi

    # 4. Deep search (slow, but limited depth)
    local found
    found=$( (find -L /usr/local /opt "${HOME}" -maxdepth 4 -name "$cmd" -executable 2>/dev/null || true) | head -n 1)
    if [[ -n "$found" ]]; then
        DISCOVERED_BIN="$found"
        export PATH="$(dirname "$found"):$PATH"
        return 0
    fi

    return 1
}

languages() {
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then return; fi

    # Ensure we have a working PATH initially
    reload_path || true

    export PIP_DISABLE_PIP_VERSION_CHECK=1
    resolve_configuration "pip" "pip"

    if [[ -n "$RESOLVED_PKGS" ]]; then
        local bin_parts
        IFS=' ' read -r -a bin_parts <<< "$RESOLVED_BIN"
        local base_cmd="${bin_parts[0]}"
        
        if discover_binary "$base_cmd"; then
            local pip_exec="$DISCOVERED_BIN"
            if [[ ${#bin_parts[@]} -gt 1 ]]; then
                pip_exec="$DISCOVERED_BIN ${bin_parts[@]:1}"
            fi
            
            info "[Pip] Installing using '$pip_exec'..."
            local pip_args=("install" "--user" "--upgrade")
            if $pip_exec install --help 2>&1 | grep -q "break-system-packages"; then
                pip_args+=("--break-system-packages")
            fi
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $pip_exec "${pip_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Pip] Failed"
        else
            warn "[Pip] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "npm" "npm"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        local base_cmd
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        if discover_binary "$base_cmd"; then
            info "[Npm] Installing using '$DISCOVERED_BIN'..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $DISCOVERED_BIN install -g "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Npm] Failed"
        else
            warn "[Npm] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "go" "go"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        local base_cmd
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        
        if discover_binary "$base_cmd"; then
            info "[Go] Installing using '$DISCOVERED_BIN'..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            for pkg in "${pkg_array[@]}"; do
                local target="$pkg"
                if [[ "$pkg" != *"@"* ]]; then target="$pkg@latest"; fi
                $DISCOVERED_BIN install "$target" >>"${LOG_FILE}" 2>&1 || warn "[Go] Failed: $target"
            done
        else
            warn "[Go] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "cargo" "cargo"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        local base_cmd
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')

        if discover_binary "$base_cmd"; then
            local cargo_bin="$DISCOVERED_BIN"
            
            # Self-healing toolchain
            if ! "$cargo_bin" --version >/dev/null 2>&1; then
                local r_bin=""
                if command -v rustup >/dev/null 2>&1; then r_bin=$(command -v rustup)
                else r_bin="$(dirname "$cargo_bin")/rustup"; fi
                
                if [[ -x "$r_bin" ]]; then
                    info "[Cargo] Toolchain found but inactive. Initializing via rustup..."
                    $r_bin default stable >>"${LOG_FILE}" 2>&1 || true
                fi
            fi
            
            local cargo_home="${HOME}/.cargo"
            mkdir -p "${cargo_home}/bin"
            
            info "[Cargo] Installing packages using '$cargo_bin'..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            
            # Install packages one by one for better resilience
            for pkg in "${pkg_array[@]}"; do
                info "  > Installing: $pkg"
                "$cargo_bin" install --root "${cargo_home}" "$pkg" >>"${LOG_FILE}" 2>&1 || warn "[Cargo] Failed: $pkg"
            done
            
            if [[ "$(id -u)" -eq 0 ]]; then
                chown -R "${USER}:${USER}" "${cargo_home}" || true
            fi
        else
            warn "[Cargo] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "gem" "gem"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        local base_cmd
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        if discover_binary "$base_cmd"; then
            local gem_bin="$DISCOVERED_BIN"
            info "[Gem] Installing packages using '$gem_bin'..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            for pkg in "${pkg_array[@]}"; do
                "$gem_bin" install --no-document "$pkg" >>"${LOG_FILE}" 2>&1 || ensure_root "$gem_bin" install --no-document "$pkg" >>"${LOG_FILE}" 2>&1 || warn "[Gem] Failed: $pkg"
            done
        else
            warn "[Gem] Skipped. '$base_cmd' not found."
        fi
    fi

    # ... (lolcat fix remains) ...


    # Fix for lolcat LoadError (Ruby version mismatch)
    if command -v lolcat >/dev/null 2>&1; then
        if ! lolcat --version >/dev/null 2>&1; then
            info "[Fix] lolcat appears broken. Attempting to fix via gem..."
            if command -v gem >/dev/null 2>&1; then
                gem install lolcat >>"${LOG_FILE}" 2>&1 || ensure_root gem install lolcat >>"${LOG_FILE}" 2>&1
            fi
        fi
    fi
}

languages
