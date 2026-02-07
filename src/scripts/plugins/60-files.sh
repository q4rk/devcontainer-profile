#!/bin/bash

files() {
    local has_files
    has_files=$(jq '.files | if . == null then "no" else "yes" end' "${USER_CONFIG_PATH}")
    [[ "$has_files" == "\"no\"" ]] && return

    info "[Files] Linking dotfiles..."
    jq -c '.files[]?' "${USER_CONFIG_PATH}" | while read -r item; do
        local src tgt
        src=$(echo "$item" | jq -r '.source')
        tgt=$(echo "$item" | jq -r '.target')

        src="${src/#\~/$HOME}"
        tgt="${tgt/#\~/$HOME}"
        src=$(eval echo "$src")
        tgt=$(eval echo "$tgt")

        if [[ -e "$src" ]]; then
            if [[ -d "$tgt" ]] && [[ ! -L "$tgt" ]]; then
                warn "[Files] Target $tgt is a directory. Backing up..."
                mv "$tgt" "${tgt}.bak"
            elif [[ -f "$tgt" ]] && [[ ! -L "$tgt" ]]; then
                mv "$tgt" "${tgt}.bak"
            fi

            mkdir -p "$(dirname "$tgt")"
            ln -sf "$src" "$tgt"
            info "[Files] Linked $src -> $tgt"
        else
            warn "[Files] Source missing: $src"
        fi
    done
}

files
