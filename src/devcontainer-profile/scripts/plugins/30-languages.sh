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
    if command -v "$cmd" >/dev/null 2>&1; then 
        DISCOVERED_BIN=$(command -v "$cmd")
        return 0 
    fi

    # 2. Check common locations (fast)
    local common_paths=(
        "${HOME}/.local/bin"
        "${HOME}/go/bin"
        "${HOME}/.cargo/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/usr/local/go/bin"
        "/usr/local/cargo/bin"
        "/usr/local/rustup/bin"
        "/usr/lib/go/bin"
        "/usr/games"
        "/home/linuxbrew/.linuxbrew/bin"
        "/opt/homebrew/bin"
    )
    for p in "${common_paths[@]}"; do
        if [[ -x "$p/$cmd" ]]; then
            info "  [Discovery] Found '$cmd' in $p"
            export PATH="$p:$PATH"
            DISCOVERED_BIN="$p/$cmd"
            return 0
        fi
    done

    # 3. Deep search (slow)
    info "  [Discovery] Searching for '$cmd' in /usr/local, /opt, /usr/lib, and ${HOME}..."
    local found
    # We use a subshell and temporary file to avoid pipe issues and capture the result reliably
    found=$( (find -L /usr/local /opt /usr/lib "${HOME}" -maxdepth 6 -name "$cmd" -executable 2>/dev/null || true) | head -n 1)
    if [[ -n "$found" ]]; then
        info "  [Discovery] Deep search found '$cmd' at $found"
        local dir
        dir=$(dirname "$found")
        export PATH="$dir:$PATH"
        DISCOVERED_BIN="$found"
        return 0
    fi

    return 1
}

languages() {
    if [[ -z "${USER_CONFIG_PATH-}" ]]; then
        warn "[Languages] USER_CONFIG_PATH not set. Skipping."
        return
    fi
    if [[ ! -f "${USER_CONFIG_PATH}" ]]; then
        warn "[Languages] Config file not found: ${USER_CONFIG_PATH}. Skipping."
        return
    fi

    export PIP_DISABLE_PIP_VERSION_CHECK=1
    resolve_configuration "pip" "pip"

    if [[ -n "$RESOLVED_PKGS" ]]; then
        # Use simple splitting for the binary in case it is "python -m pip"
        local bin_parts
        IFS=' ' read -r -a bin_parts <<< "$RESOLVED_BIN"
        local base_cmd="${bin_parts[0]}"
        
        if discover_binary "$base_cmd"; then
            local pip_cmd="$DISCOVERED_BIN"
            # If it was "python3 -m pip", we need to reconstruct it
            if [[ ${#bin_parts[@]} -gt 1 ]]; then
                pip_cmd="$DISCOVERED_BIN ${bin_parts[@]:1}"
            fi
            info "[Pip] Installing using '$pip_cmd'..."
            local pip_args=("install" "--user" "--upgrade")
            # Check for modern flag support
            if $pip_cmd install --help 2>&1 | grep -q "break-system-packages"; then
                pip_args+=("--break-system-packages")
            fi
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $pip_cmd "${pip_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Pip] Failed"
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
            local npm_args=("install" "-g")
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $DISCOVERED_BIN "${npm_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Npm] Failed"
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
            # self-healing rust: check if cargo actually works
            if ! "$cargo_bin" --version >/dev/null 2>&1; then
                if command -v rustup >/dev/null 2>&1; then
                    info "[Cargo] Toolchain found but inactive. Initializing..."
                    rustup default stable >>"${LOG_FILE}" 2>&1 || true
                fi
            fi
            
            # Ensure the target directory exists and is owned by the user
            local cargo_home="${HOME}/.cargo"
            mkdir -p "${cargo_home}/bin"
            
            info "[Cargo] Installing packages..."
            local cargo_args=("install" "--root" "${cargo_home}")
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            
            if "$cargo_bin" "${cargo_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1; then
                info "[Cargo] Installation complete."
            else
                warn "[Cargo] Some packages failed to install. Last 20 lines of log:"
                tail -n 20 "${LOG_FILE}" >&2
            fi
            
            # Ensure ownership
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
            info "[Gem] Installing packages..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            # Gems often need sudo if not using RVM/rbenv
            local gem_args=("install" "--no-document")
            for pkg in "${pkg_array[@]}"; do
                "$gem_bin" "${gem_args[@]}" "$pkg" >>"${LOG_FILE}" 2>&1 || ensure_root "$gem_bin" "${gem_args[@]}" "$pkg" >>"${LOG_FILE}" 2>&1 || warn "[Gem] Failed: $pkg"
            done
        else
            warn "[Gem] Skipped. '$RESOLVED_BIN' not found."
        fi
    fi

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
