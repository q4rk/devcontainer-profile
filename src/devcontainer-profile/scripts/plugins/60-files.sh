#!/usr/bin/env bash

# Plugin: Files
# Manages dotfiles via symlinks

link_files() {
    local files_json
    files_json=$(jq -c '.files[]? // empty' "${USER_CONFIG_PATH}")
    [[ -z "$files_json" ]] && return

    info "[Files] Linking dotfiles..."

    echo "$files_json" | while read -r item; do
        local src tgt
        src=$(echo "$item" | jq -r '.source')
        tgt=$(echo "$item" | jq -r '.target')

        # Expand HOME
        src="${src/#\~/$HOME}"
        tgt="${tgt/#\~/$HOME}"
        
        # Skip if source missing
        if [[ ! -e "$src" ]]; then
            warn "Skipping link: Source missing ($src)"
            continue
        fi

        # Prepare target directory
        mkdir -p "$(dirname "$tgt")"

        # Handle existing target
        if [[ -e "$tgt" || -L "$tgt" ]]; then
            # If it's already a correct link, skip
            if [[ -L "$tgt" ]] && [[ "$(readlink -f "$tgt")" == "$(readlink -f "$src")" ]]; then
                continue
            fi
            
            # Backup if it's a real file
            if [[ ! -L "$tgt" ]]; then
                mv "$tgt" "${tgt}.bak"
                info "Backed up existing $tgt to ${tgt}.bak"
            else
                rm "$tgt"
            fi
        fi

        if ln -s "$src" "$tgt"; then
            info "Linked $src -> $tgt"
        else
            error "Failed to link $src"
        fi
    done
}

link_files