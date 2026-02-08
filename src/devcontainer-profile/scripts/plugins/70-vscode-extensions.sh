#!/usr/bin/env bash

# Plugin: VS Code Extensions

install_extensions() {
    # Find Code CLI
    local code_bin
    if command -v code >/dev/null; then code_bin="code"
    elif command -v code-insiders >/dev/null; then code_bin="code-insiders"
    else return; fi

    local extensions
    extensions=$(jq -r '.["vscode-extensions"][]? // empty' "${USER_CONFIG_PATH}")
    [[ -z "$extensions" ]] && return

    info "[VS Code] Installing extensions..."
    
    # Get installed list once
    local installed
    installed=$($code_bin --list-extensions | tr '[:upper:]' '[:lower:]')

    for ext in $extensions; do
        local lower_ext
        lower_ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        
        if echo "$installed" | grep -qxF "$lower_ext"; then
            continue
        fi
        
        info " > Installing $ext"
        if ! $code_bin --install-extension "$ext" --force >>"${LOG_FILE}" 2>&1; then
            warn "Failed to install $ext"
        fi
    done
}

install_extensions