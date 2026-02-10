#!/usr/bin/env bash

source "${LIB_PATH}"

run_files() {
    local has_files
    has_files=$(jq '.files | if . == null then "no" else "yes" end' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ "$has_files" == "no" ]] && return 0

    info "Files" "Linking dotfiles..."
    
    # Store currently active targets to detect deletions
    local current_targets=()
    # Read all targets into an array for comparison later
    while IFS= read -r t; do
        [[ -z "$t" || "$t" == "null" ]] && continue
        t="${t/#\~/$TARGET_HOME}"
        t=$(eval echo "$t")
        current_targets+=("$t")
    done < <(jq -r '.files[]?.target' "${USER_CONFIG_PATH}" 2>/dev/null)
    
    jq -c '.files[]?' "${USER_CONFIG_PATH}" | while read -r item; do
        [[ -z "$item" || "$item" == "null" ]] && continue
        
        local src tgt
        src=$(echo "$item" | jq -r '.source')
        tgt=$(echo "$item" | jq -r '.target')


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
                    track_managed_resource "symlinks" "$tgt"
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
            track_managed_resource "symlinks" "$tgt"
            info "Files" "Linked $src -> $tgt"
        else
            error "Files" "Failed to link $tgt"
        fi
    done

    # Any path in the managed list that is NOT in the current config is removed
    local managed_links
    managed_links=$(get_managed_resources "symlinks")
    
    # Reset managed list for fresh write
    clear_managed_resources "symlinks"

    for link in ${managed_links}; do
        local found=0
        for active in "${current_targets[@]}"; do
            [[ "$link" == "$active" ]] && found=1 && break
        done

        if [[ $found -eq 1 ]]; then
            track_managed_resource "symlinks" "$link"
        else
            if [[ -L "$link" ]]; then
                info "Files" "Removing stale link: $link"
                rm -f "$link"
            fi
        fi
    done
}

run_files