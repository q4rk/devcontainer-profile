#!/usr/bin/env bash

source "${LIB_PATH}"

run_settings() {
    local settings_json
    settings_json=$(jq -c '.["vscode-settings"] // empty' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ -z "${settings_json}" ]] && return 0

    info "VSCode" "Merging machine settings..."

    local paths=(
        "${TARGET_HOME}/.vscode-server/data/Machine"
        "${TARGET_HOME}/.vscode-server-insiders/data/Machine"
    )

    for p in "${paths[@]}"; do
        if [[ -d "$p" ]]; then
            local target_file="${p}/settings.json"
            [[ ! -f "$target_file" ]] && echo "{}" > "$target_file"
            
            local tmp_settings
            tmp_settings=$(mktemp)
            
            if jq -s '.[0] * .[1]' "$target_file" <(echo "$settings_json") > "$tmp_settings"; then
                cat "$tmp_settings" > "$target_file"
            else
                warn "VSCode" "Failed to merge settings for $p"
            fi
            rm -f "$tmp_settings"
        fi
    done
}

run_settings