#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Config with shell history enabled using discovery file
echo '{"shell-history": true, "env": {"SHELL_CHECK": "active"}}' > "$HOME/.devcontainer.profile"

# Trigger apply (as user)
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications for Bash
check "bashrc: env sourced" grep ".devcontainer.profile_env" "$HOME/.bashrc"
check "bashrc: history configured" grep "HISTFILE" "$HOME/.bashrc"

# Verifications for Zsh
touch "$HOME/.zshrc"
/usr/local/share/devcontainer-profile/scripts/apply.sh
check "zshrc: env sourced" grep ".devcontainer.profile_env" "$HOME/.zshrc"
check "zshrc: history configured" grep "HISTFILE" "$HOME/.zshrc"

reportResults
