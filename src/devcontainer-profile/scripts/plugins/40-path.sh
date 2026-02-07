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
    done < <(find /usr/local /opt "${HOME}" -maxdepth 6 -type d -name bin 2>/dev/null | grep -vE "^/usr/local/bin$|^/usr/bin$|^/bin$")

    # Hardcoded Critical Paths (Pip, Games, Rust, Go)
    local critical_paths=(
        "/usr/games"               # sl, fortune, cowsay
        "${HOME}/.local/bin"       # pip install --user (thefuck, glances)
        "${HOME}/go/bin"           # go install
        "${HOME}/.cargo/bin"       # cargo install
        "/usr/local/go/bin"        # Feature: Go standard path
        "/usr/local/cargo/bin"     # Feature: Rust standard path
        "/usr/local/rustup/bin"    # Rustup path
        "/usr/lib/go/bin"          # Alternate Go path
        "/home/linuxbrew/.linuxbrew/bin" # Linuxbrew
    )

    for p in "${critical_paths[@]}"; do
        bins_to_persist+=("$p")
    done

    # Build the Export Script
    # We use a runtime check for each path to avoid duplicates if the script is sourced multiple times
    declare -A unique_map
    echo "# .devcontainer.profile paths" > "${USER_PATH_FILE}.tmp"
    for dir in "${bins_to_persist[@]}"; do
        if [[ -z "${unique_map[$dir]-}" ]]; then
            echo "case \":\$PATH:\" in *\":${dir}:\"*) ;; *) export PATH=\"\$PATH:${dir}\" ;; esac" >> "${USER_PATH_FILE}.tmp"
            unique_map["$dir"]=1
            info "  Persisting: $dir"
            
            # Also update the current shell session's PATH for subsequent plugins
            case ":$PATH:" in *":${dir}:"*) ;; *) export PATH="$PATH:${dir}" ;; esac
        fi
    done
    mv "${USER_PATH_FILE}.tmp" "${USER_PATH_FILE}"

    # Inject into shell configs (Bash AND Zsh)
    local source_cmd="\n# .devcontainer.profile\n[ -f \"${USER_PATH_FILE}\" ] && . \"${USER_PATH_FILE}\"\n"

        if ! grep -qF "${USER_PATH_FILE}" "${HOME}/.bashrc"; then
            echo -e "$source_cmd" >> "${HOME}/.bashrc"
        fi

        touch "${HOME}/.zshrc"
        if ! grep -qF "${USER_PATH_FILE}" "${HOME}/.zshrc"; then
            echo -e "$source_cmd" >> "${HOME}/.zshrc"
        fi
}

path_reconciliation
