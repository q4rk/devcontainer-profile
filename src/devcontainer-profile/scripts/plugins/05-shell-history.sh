#!/bin/bash
# 05-shell-history.sh - Persist shell history
source "${LIB_PATH}"

run_history() {
    local enabled
    enabled=$(get_config_val "shell-history" "true")
    [[ "$enabled" == "false" ]] && return 0

    local history_size
    history_size=$(get_config_val "shell-history-size" "10000")
    local history_root="${WORKSPACE}/shellhistory"

    info "History" "Configuring persistence (size: ${history_size})..."
    
    mkdir -p "${history_root}"
    ensure_root chown -R "${TARGET_USER}:${TARGET_USER}" "${history_root}"

    # Bash Configuration
    local bash_config="
export HISTFILE=${history_root}/.bash_history
export HISTSIZE=${history_size}
export HISTFILESIZE=${history_size}
export PROMPT_COMMAND=\"\${PROMPT_COMMAND:+\$PROMPT_COMMAND; }history -a\"
"
    update_file_idempotent "${TARGET_HOME}/.bashrc" "SHELL_HISTORY" "${bash_config}"

    # Zsh Configuration
    local zsh_config="
export HISTFILE=${history_root}/.zsh_history
export HISTSIZE=${history_size}
export SAVEHIST=${history_size}
setopt APPEND_HISTORY
setopt SHARE_HISTORY
"
    update_file_idempotent "${TARGET_HOME}/.zshrc" "SHELL_HISTORY" "${zsh_config}"
}

run_history