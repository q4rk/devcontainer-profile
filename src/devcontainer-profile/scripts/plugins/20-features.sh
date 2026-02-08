#!/bin/bash
# 20-features.sh - Install OCI Features via feature-installer
source "${LIB_PATH}"

run_features() {
    if ! command -v feature-installer >/dev/null 2>&1; then
        warn "Features" "feature-installer binary not found."
        return 0
    fi

    local features_json
    features_json=$(jq -c '.features[]? | select(. != null)' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ -z "${features_json}" ]] && return 0

    local temp_dir
    temp_dir=$(mktemp -d)
    chmod 777 "$temp_dir"

    echo "${features_json}" | while read -r feature; do
        local id
        id=$(echo "$feature" | jq -r '.id')
        
        # Build options array safely
        local options=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && options+=("--option" "$line")
        done < <(echo "$feature" | jq -r '(.options // {}) | to_entries[] | .key + "=" + (.value | tostring)')

        info "Features" "Installing: ${id}"
        if ! TMPDIR="$temp_dir" ensure_root feature-installer feature install "$id" "${options[@]}"; then
            error "Features" "Failed to install ${id}"
        fi
    done

    rm -rf "$temp_dir"
}

run_features