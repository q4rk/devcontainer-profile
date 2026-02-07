#!/bin/bash

files() {
    local has_files
    has_files=$(jq '.files | if . == null then "no" else "yes" end' "${USER_CONFIG_PATH}")
    [[ "$has_files" == "\"no\"" ]] && return

    info "[Files] Linking dotfiles..."
    jq -c '.files[]?' "${USER_CONFIG_PATH}" | while read -r item; do
        [[ -z "$item" || "$item" == "null" ]] && continue
        local src tgt
        src=$(echo "$item" | jq -r '.source')
        tgt=$(echo "$item" | jq -r '.target')

        # Expand ~ manually to avoid eval issues in some contexts
        src="${src/#\~/$HOME}"
        tgt="${tgt/#\~/$HOME}"

        if [[ -e "$src" ]]; then
            # If target exists and is NOT already a link to the correct source
            if [[ -e "$tgt" ]]; then
                if [[ -L "$tgt" ]]; then
                    local current_link
                    current_link=$(readlink -f "$tgt")
                    if [[ "$current_link" == "$(readlink -f "$src")" ]]; then
                        info "  > Already linked: $tgt"
                        continue
                    fi
                    info "  > Replacing existing link: $tgt"
                    rm -f "$tgt"
                else
                    info "  > Backing up existing file/dir: $tgt"
                    mv -f "$tgt" "${tgt}.bak"
                fi
            fi

            mkdir -p "$(dirname "$tgt")"
            if ln -sf "$src" "$tgt"; then
                info "  > Linked $src -> $tgt"
            else
                warn "  > Failed to link $src -> $tgt"
            fi
        else
            warn "  > Source missing: $src"
        fi
    done
}

files
