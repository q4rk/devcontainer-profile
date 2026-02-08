#!/usr/bin/env bash

# Plugin: Scripts
# Runs arbitrary user scripts

run_scripts() {
    local count
    count=$(jq '.scripts // [] | length' "${USER_CONFIG_PATH}")
    [[ "$count" == "0" ]] && return

    info "[Scripts] Executing $count user scripts..."

    # Extract scripts to a temp file to avoid eval complexity
    script_file="${WORKSPACE}/tmp/user_scripts_$(date +%s).sh"
    local script_file
    
    jq -r '.scripts[]' "${USER_CONFIG_PATH}" > "$script_file"
    
    # Execute line by line for better logging
    local i=1
    while read -r line; do
        info " > Script #$i: $line"
        if ! eval "$line" >>"${LOG_FILE}" 2>&1; then
            warn "Script #$i failed."
        fi
        i=$((i+1))
    done < "$script_file"
    
    rm "$script_file"
}

run_scripts