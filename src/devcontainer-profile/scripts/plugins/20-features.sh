#!/usr/bin/env bash

# Plugin: Features
# Installs OCI Features via feature-installer

install_features() {
    if ! command -v feature-installer >/dev/null 2>&1; then return; fi

    # Check if features exist
    if [[ $(jq '.features | length' "${USER_CONFIG_PATH}") == "0" ]]; then return; fi

    info "[Features] Processing..."

    # Use a temp directory
    local tmp_feat_dir="${WORKSPACE}/tmp/features-$$"
    mkdir -p "$tmp_feat_dir"

    # Iterate through features
    # usage of base64 to handle complex json objects in loop
    jq -r '.features[]? | @base64' "${USER_CONFIG_PATH}" | while read -r feat_b64; do
        local feat_json
        feat_json=$(echo "$feat_b64" | base64 -d)
        
        local id
        id=$(echo "$feat_json" | jq -r '.id')
        
        # Parse options into array
        local opts_args=()
        while IFS="=" read -r key val; do
            if [[ -n "$key" ]]; then
                opts_args+=("--option" "${key}=${val}")
            fi
        done < <(echo "$feat_json" | jq -r '(.options // {}) | to_entries[] | .key + "=" + (.value | tostring)')

        info "[Features] Installing $id"
        if ! TMPDIR="$tmp_feat_dir" ensure_root feature-installer feature install "$id" "${opts_args[@]}"; then
            error "[Features] Failed to install $id"
        fi
    done

    rm -rf "$tmp_feat_dir"
}

install_features