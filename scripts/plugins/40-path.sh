#!/bin/bash

path_reconciliation() {
    info "[Path] Reconciling..."

    # Start with a fresh list of paths we MUST ensure are persisted
    # We do NOT check if they are currently in $PATH, because apply.sh
    # might have added them temporarily. We want them permanent.
    local bins_to_persist=()

    # Scan for dynamic OCI Feature paths (e.g. /usr/local/hugo/bin)
    # We only accept directories that actually exist.
    while IFS= read -r dir; do
        bins_to_persist+=("$dir")
    done < <(find /usr/local -maxdepth 3 -type d -name bin 2>/dev/null | grep -v "^/usr/local/bin$")

    # Hardcoded Critical Paths (Pip, Games, Rust, Go)
    local critical_paths=(
        "/usr/games"               # sl, fortune, cowsay
        "${HOME}/.local/bin"       # pip install --user (thefuck, glances)
        "${HOME}/go/bin"           # go install
        "${HOME}/.cargo/bin"       # cargo install
        "/usr/local/go/bin"        # Feature: Go standard path
        "/usr/local/cargo/bin"     # Feature: Rust standard path
    )

    for p in "${critical_paths[@]}"; do
        if [[ -d "$p" ]]; then bins_to_persist+=("$p"); fi
    done

    # Build the Export String (Filtering Duplicates)
    # We use an associative array to deduplicate the list we just built
    declare -A unique_map
    local path_string=""

    for dir in "${bins_to_persist[@]}"; do
        if [[ -z "${unique_map[$dir]-}" ]]; then
            path_string="${path_string}:${dir}"
            unique_map["$dir"]=1
            info "  Persisting: $dir"
        fi
    done

    if [[ -n "$path_string" ]]; then
        # We overwrite the file to ensure it's clean and up-to-date
        echo "export PATH=\"\$PATH${path_string}\"" > "${USER_PATH_FILE}.tmp"
        mv "${USER_PATH_FILE}.tmp" "${USER_PATH_FILE}"

        # Inject into shell configs (Bash AND Zsh)
        # We use a safe appending logic that checks if the file exists before sourcing
        local source_cmd="\n# .devcontainer.profile\n[ -f \"${USER_PATH_FILE}\" ] && . \"${USER_PATH_FILE}\"\n"

        if ! grep -qF "${USER_PATH_FILE}" "${HOME}/.bashrc"; then
            echo -e "$source_cmd" >> "${HOME}/.bashrc"
        fi

        touch "${HOME}/.zshrc"
        if ! grep -qF "${USER_PATH_FILE}" "${HOME}/.zshrc"; then
            echo -e "$source_cmd" >> "${HOME}/.zshrc"
        fi

        export PATH="$PATH${path_string}"
    fi
}

path_reconciliation
