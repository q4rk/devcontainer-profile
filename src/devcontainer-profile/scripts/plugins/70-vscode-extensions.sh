#!/bin/bash
# 70-vscode-extensions.sh
source "${LIB_PATH}"

run_vscode_ext() {
    local exts
    exts=$(get_config_keys "vscode-extensions")
    [[ -z "$exts" ]] && return 0

    local code_bin=""
    if command -v code >/dev/null 2>&1; then code_bin="code";
    elif command -v code-insiders >/dev/null 2>&1; then code_bin="code-insiders"; fi

    if [[ -z "$code_bin" ]]; then return 0; fi

    info "VSCode" "Checking extensions..."
    
    # Cache installed extensions to avoid slow calls inside loop
    local installed
    installed=$($code_bin --list-extensions | tr '[:upper:]' '[:lower:]')

    while IFS= read -r ext; do
        [[ -z "$ext" ]] && continue
        local ext_lower
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        
        if echo "$installed" | grep -qF "$ext_lower"; then
            continue
        fi

        info "VSCode" "Installing $ext..."
        $code_bin --install-extension "$ext" --force >/dev/null 2>&1 || warn "VSCode" "Failed to install $ext"
    done <<< "$exts"
}

run_vscode_ext