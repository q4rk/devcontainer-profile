#!/bin/bash

vscode_extensions() {
    local id_lower
    local ext_ids=()
    while IFS='' read -r line; do ext_ids+=("$line"); done < <(
        jq -r '.["vscode-extensions"][]? // empty' "${USER_CONFIG_PATH}"
    )

    [[ ${#ext_ids[@]} -eq 0 ]] && return

    info "[VS Code] Checking extensions..."

    local code_bin=""
    if command -v code >/dev/null 2>&1; then
        code_bin="code"
    elif command -v code-insiders >/dev/null 2>&1; then
        code_bin="code-insiders"
    else
        warn "[VS Code] CLI not found. Skipping extension installation."
        return
    fi

    # Get currently installed extensions to skip duplicates
    local installed_exts
    installed_exts=$($code_bin --list-extensions 2>/dev/null | tr -d '\0' | tr '[:upper:]' '[:lower:]')
    info "  Currently installed extensions: $(echo "${installed_exts}" | xargs)"

    for id in "${ext_ids[@]}"; do
        id_lower=$(echo "$id" | tr '[:upper:]' '[:lower:]')
        if echo "${installed_exts}" | grep -qxF "${id_lower}"; then
            info "  > Already installed: ${id}"
        else
            info "  > Installing: ${id}"
            # Use --force to ensure it doesn't hang on prompts
            if ! $code_bin --install-extension "${id}" --force >>"${LOG_FILE}" 2>&1; then
                 warn "Failed to install extension: ${id}"
            fi
        fi
    done
}

vscode_extensions
