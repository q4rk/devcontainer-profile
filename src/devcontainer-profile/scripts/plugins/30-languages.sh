#!/bin/bash

# Helper to safely resolve packages regardless of config format
resolve_configuration() {
    local key="$1"
    local default_bin="$2"

    RESOLVED_BIN=""
    RESOLVED_PKGS=""

    local raw_config
    raw_config=$(jq -c ".\"$key\" // empty" "${USER_CONFIG_PATH}")
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
}

languages() {
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    resolve_configuration "pip" "pip"

    if [[ -n "$RESOLVED_PKGS" ]]; then
        # Use simple splitting for the binary in case it is "python -m pip"
        local bin_parts
        IFS=' ' read -r -a bin_parts <<< "$RESOLVED_BIN"
        local base_cmd="${bin_parts[0]}"
        if command -v "$base_cmd" >/dev/null 2>&1; then
            info "[Pip] Installing using '$RESOLVED_BIN'..."
            local pip_args=("install" "--user" "--upgrade")
            # Check for modern flag support
            if $RESOLVED_BIN install --help 2>&1 | grep -q "break-system-packages"; then
                pip_args+=("--break-system-packages")
            fi
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $RESOLVED_BIN "${pip_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Pip] Failed"
        else
            warn "[Pip] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "npm" "npm"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        local base_cmd
        if command -v "$base_cmd" >/dev/null 2>&1; then
            info "[Npm] Installing using '$RESOLVED_BIN'..."
            local npm_args=("install" "-g")
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $RESOLVED_BIN "${npm_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Npm] Failed"
        else
            warn "[Npm] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "go" "go"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        local base_cmd
        if command -v "$base_cmd" >/dev/null 2>&1; then
            info "[Go] Installing using '$RESOLVED_BIN'..."
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            for pkg in "${pkg_array[@]}"; do
                local target="$pkg"
                if [[ "$pkg" != *"@"* ]]; then target="$pkg@latest"; fi
                $RESOLVED_BIN install "$target" >>"${LOG_FILE}" 2>&1 || warn "[Go] Failed: $target"
            done
        else
            warn "[Go] Skipped. '$base_cmd' not found."
        fi
    fi

    resolve_configuration "cargo" "cargo"
    if [[ -n "$RESOLVED_PKGS" ]]; then
        base_cmd=$(echo "$RESOLVED_BIN" | awk '{print $1}')
        local base_cmd
        if command -v "$base_cmd" >/dev/null 2>&1; then
            # self-healing rust
            if ! "$base_cmd" --version >/dev/null 2>&1; then
                if command -v rustup >/dev/null 2>&1; then
                    info "[Cargo] Initializing toolchain..."
                    rustup default stable >>"${LOG_FILE}" 2>&1 || true
                fi
            fi
            info "[Cargo] Installing using '$RESOLVED_BIN'..."
            local cargo_args=("install")
            local pkg_array=()
            while IFS= read -r line; do [[ -n "$line" ]] && pkg_array+=("$line"); done <<< "$RESOLVED_PKGS"
            $RESOLVED_BIN "${cargo_args[@]}" "${pkg_array[@]}" >>"${LOG_FILE}" 2>&1 || warn "[Cargo] Failed"
        else
            warn "[Cargo] Skipped. '$base_cmd' not found."
        fi
    fi
}

languages
