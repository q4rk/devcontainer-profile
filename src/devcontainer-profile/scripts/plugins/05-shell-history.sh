#!/usr/bin/env bash

# Plugin: Shell History
# Configures persistent shell history

configure_history() {
    local enabled
    enabled=$(get_config_value '.["shell-history"]' "true")
    
    if [[ "$enabled" == "false" ]]; then return; fi

    local size
    size=$(get_config_value '.["shell-history-size"]' "10000")
    local history_dir="${WORKSPACE}/shellhistory"

    mkdir -p "${history_dir}"
    ensure_root chown -R "$(id -u):$(id -g)" "${history_dir}"

    info "[Shell History] Persistence enabled (Size: $size)."

    # Bash
    local bash_snip="export HISTFILE=${history_dir}/.bash_history
export HISTSIZE=${size}
export HISTFILESIZE=${size}
export PROMPT_COMMAND=\"\${PROMPT_COMMAND:+\$PROMPT_COMMAND; }history -a\""
    
    safe_append_if_missing "HISTFILE=${history_dir}/.bash_history" "$HOME/.bashrc" "$bash_snip"

    # Zsh
    local zsh_snip="export HISTFILE=${history_dir}/.zsh_history
export HISTSIZE=${size}
export SAVEHIST=${size}
setopt APPEND_HISTORY
setopt SHARE_HISTORY"

    if [[ -f "$HOME/.zshrc" ]]; then
        safe_append_if_missing "HISTFILE=${history_dir}/.zsh_history" "$HOME/.zshrc" "$zsh_snip"
    fi

    # Fish
    if command -v fish >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/fish"
        local fish_target="$HOME/.local/share/fish/fish_history"
        # Only link if it's not already linked to the right place
        if [[ "$(readlink -f "$fish_target" 2>/dev/null)" != "${history_dir}/fish_history" ]]; then
             mkdir -p "$(dirname "$fish_target")"
             rm -rf "$fish_target"
             ln -s "${history_dir}/fish_history" "$fish_target"
        fi
    fi
}

configure_history