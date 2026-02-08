#!/usr/bin/env bash

# Plugin: Env
# Injects environment variables

inject_env() {
    local env_file="${TARGET_HOME}/.devcontainer_profile_env"
    
    # Generate Env File
    if ! jq -r '.env | to_entries[]? | "export \(.key)=\"\(.value | tostring)\""' "${USER_CONFIG_PATH}" > "${env_file}.tmp"; then
        return
    fi
    
    if [[ ! -s "${env_file}.tmp" ]]; then
        rm "${env_file}.tmp"
        return
    fi

    mv "${env_file}.tmp" "${env_file}"
    info "[Env] Environment variables updated."

    local source_cmd="[ -f \"$env_file\" ] && set -o allexport && . \"$env_file\" && set +o allexport"

    safe_append_if_missing ".devcontainer_profile_env" "$HOME/.bashrc" "$source_cmd"
    if [[ -f "$HOME/.zshrc" ]]; then
        safe_append_if_missing ".devcontainer_profile_env" "$HOME/.zshrc" "$source_cmd"
    fi
}

inject_env