#!/bin/bash
# 60-files.sh - Dotfiles symlinking
source "${LIB_PATH}"

run_files() {
    # Check if files key exists
    local has_files
    has_files=$(jq '.files | if . == null then "no" else "yes" end' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ "$has_files" == "no" ]] && return 0

    info "Files" "Linking dotfiles..."
    
    jq -c '.files[]?' "${USER_CONFIG_PATH}" | while read -r item; do
        [[ -z "$item" || "$item" == "null" ]] && continue
        
        local src tgt
        src=$(echo "$item" | jq -r '.source')
        tgt=$(echo "$item" | jq -r '.target')

        # Expansion
        src="${src/#\~/$TARGET_HOME}"
        tgt="${tgt/#\~/$TARGET_HOME}"
        src=$(eval echo "$src") # Expand vars like $HOME
        tgt=$(eval echo "$tgt")

        if [[ ! -e "$src" ]]; then
            warn "Files" "Source missing: $src"
            continue
        fi

        # Handle existing target
        if [[ -e "$tgt" ]]; then
            if [[ -L "$tgt" ]]; then
                # Check if already points to correct place
                local current_link
                current_link=$(readlink -f "$tgt")
                local src_abs
                src_abs=$(readlink -f "$src")
                
                if [[ "$current_link" == "$src_abs" ]]; then
                    continue
                fi
                rm -f "$tgt"
            else
                mv "$tgt" "${tgt}.bak"
            fi
        fi

        mkdir -p "$(dirname "$tgt")"
        if ln -sf "$src" "$tgt"; then
            safe_chown "${TARGET_USER}" "$tgt"
            info "Files" "Linked $src -> $tgt"
        else
            error "Files" "Failed to link $tgt"
        fi
    done
}

run_files