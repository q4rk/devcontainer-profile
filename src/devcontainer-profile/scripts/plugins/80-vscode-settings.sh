#!/usr/bin/env bash

# Plugin: VS Code Settings
# Merges user settings into Machine settings

apply_settings() {
    local settings
    settings=$(jq -c '.["vscode-settings"] // empty' "${USER_CONFIG_PATH}")
    [[ -z "$settings" ]] && return

    info "[VS Code] Applying machine settings..."

    local paths=(
        "$HOME/.vscode-server/data/Machine/settings.json"
        "$HOME/.vscode-server-insiders/data/Machine/settings.json"
    )

    for target in "${paths[@]}"; do
        if [[ -d "$(dirname "$target")" ]]; then
            # Create if missing
            [[ ! -f "$target" ]] && echo "{}" > "$target"

            # Merge safely using temp file
            local tmp_out="${target}.tmp"
            if jq -s '.[0] * .[1]' "$target" <(echo "$settings") > "$tmp_out"; then
                mv "$tmp_out" "$target"
                info "Updated settings at $target"
            else
                rm -f "$tmp_out"
                warn "Failed to merge settings for $target"
            fi
        fi
    done
}

apply_settings