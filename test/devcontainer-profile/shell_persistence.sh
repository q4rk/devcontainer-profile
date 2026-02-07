#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Config with shell history enabled
mkdir -p "$HOME/.devcontainer-profile"
echo '{"shell-history": true, "env": {"SHELL_CHECK": "active"}}' > "$HOME/.devcontainer-profile/config.json"

# Trigger apply
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications for Bash
check "bashrc: env sourced" grep ".devcontainer.profile_env" "$HOME/.bashrc"
check "bashrc: history configured" grep "HISTFILE" "$HOME/.bashrc"

# Verifications for Zsh (even if not currently running, the file should be updated)
touch "$HOME/.zshrc"
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh
check "zshrc: env sourced" grep ".devcontainer.profile_env" "$HOME/.zshrc"
check "zshrc: history configured" grep "HISTFILE" "$HOME/.zshrc"

reportResults
