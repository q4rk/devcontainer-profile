#!/bin/bash

vscode_settings() {
    local settings_json
    settings_json=$(jq -c '.["vscode-settings"] // empty' "${USER_CONFIG_PATH}")

    [[ -z "${settings_json}" || "${settings_json}" == "null" ]] && return

    info "[VS Code] Applying machine settings..."

    local server_paths=(
        "${HOME}/.vscode-server/data/Machine"
        "${HOME}/.vscode-server-insiders/data/Machine"
    )

    for base_path in "${server_paths[@]}"; do
        # We only apply if the directory exists (indicating that server version is in use)
        if [[ -d "${base_path}" ]]; then
            local target="${base_path}/settings.json"
            
            if [[ ! -f "${target}" ]]; then
                echo "{}" > "${target}"
            fi

            # We use a temporary file to ensure we don't truncate the file on error
            if tmp_settings=$(jq -s '.[0] * .[1]' "${target}" <(echo "${settings_json}") 2>/dev/null); then
                echo "${tmp_settings}" > "${target}"
                info "  > Applied to: $(basename $(dirname $(dirname "${base_path}")))"
            else
                warn "  > Failed to merge settings for ${base_path}"
            fi
        fi
    done
}

vscode_settings
