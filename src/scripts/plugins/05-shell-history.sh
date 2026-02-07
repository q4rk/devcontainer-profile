#!/bin/bash

shell_history() {
    local history_root="${WORKSPACE}/shellhistory"

    # enabled by default
    local enabled
    enabled=$(jq -r '.["shell-history"] // "true"' "${USER_CONFIG_PATH}" 2>/dev/null)
    [[ "$enabled" == "false" ]] && return

    # configurable history size (default to 10000)
    local history_size
    history_size=$(jq -r '.["shell-history-size"] // 10000' "${USER_CONFIG_PATH}" 2>/dev/null)

    info "[Shell History] Activating persistence (size: ${history_size})..."

    mkdir -p "${history_root}"
    if [[ "$(stat -c '%U' "${history_root}" 2>/dev/null)" != "$(id -un)" ]]; then
        ensure_root chown -R "$(id -u):$(id -g)" "${history_root}" >/dev/null 2>&1 || true
    fi

    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "HISTFILE=${history_root}/.bash_history" "$HOME/.bashrc"; then
        cat << EOF >> "$HOME/.bashrc"

# .devcontainer.profile shell-history
if [[ -z "\${HISTFILE_OLD-}" ]]; then
    export HISTFILE_OLD=\$HISTFILE
fi
export HISTFILE=${history_root}/.bash_history
export HISTSIZE=${history_size}
export HISTFILESIZE=${history_size}
# Append 'history -a' safely to existing PROMPT_COMMAND
export PROMPT_COMMAND="\${PROMPT_COMMAND:+\$PROMPT_COMMAND; }history -a"
EOF
    fi

    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "HISTFILE=${history_root}/.zsh_history" "$HOME/.zshrc"; then
        cat << EOF >> "$HOME/.zshrc"

# .devcontainer.profile shell-history
export HISTFILE=${history_root}/.zsh_history
export HISTSIZE=${history_size}
export SAVEHIST=${history_size}
setopt APPEND_HISTORY
setopt SHARE_HISTORY
EOF
    fi

    if command -v fish >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/fish"
        local fish_config="$HOME/.config/fish/config.fish"
        if ! grep -q "${history_root}/fish_history" "$fish_config" 2>/dev/null; then
            cat << EOF >> "$fish_config"

# .devcontainer.profile shell-history
if [ -z "\$XDG_DATA_HOME" ];
    set history_location ~/.local/share/fish/fish_history
else
    set history_location \$XDG_DATA_HOME/fish/fish_history
end

if [ -f \$history_location ] && [ ! -L \$history_location ];
    mv \$history_location "\$history_location-old"
end

[ -L \$history_location ] || ln -fs ${history_root}/fish_history \$history_location
EOF
        fi
    fi
}

shell_history
