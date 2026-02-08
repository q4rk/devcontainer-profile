#!/bin/bash
set -e
source dev-container-features-test-lib

echo '{"shell-history": true}' > "$HOME/.devcontainer.profile"

/usr/local/share/devcontainer-profile/scripts/apply.sh

check "bash: HISTFILE configured" grep "HISTFILE" "$HOME/.bashrc"

# Mock Zsh existence to test injection logic
touch "$HOME/.zshrc"
/usr/local/share/devcontainer-profile/scripts/apply.sh
check "zsh: HISTFILE configured" grep "HISTFILE" "$HOME/.zshrc"

reportResults