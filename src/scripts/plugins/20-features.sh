#!/bin/bash

oci_features() {
    if ! command -v feature-installer >/dev/null 2>&1; then return; fi

    local features_json
    features_json=$(jq -c '.features[]? | select(. != null)' "${USER_CONFIG_PATH}")
    [[ -z "${features_json}" ]] && return

    info "[Features] Processing..."
    ensure_root mount --bind "${WORKSPACE}/tmp" /tmp
    trap 'ensure_root umount -l /tmp || true' RETURN

    echo "${features_json}" | while read -r feature; do
        local id
        id=$(echo "$feature" | jq -r '.id')

        local options=()
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            options+=("--option" "$line")
        done < <(echo "$feature" | jq -r '(.options // {}) | to_entries[] | .key + "=" + (.value | tostring)')

        info "[Features] Installing: ${id}"

        if ! ensure_root feature-installer feature install "$id" "${options[@]}" >>"${LOG_FILE}" 2>&1; then
            error "[Features] Failed: ${id}"
        fi
    done
}

oci_features
