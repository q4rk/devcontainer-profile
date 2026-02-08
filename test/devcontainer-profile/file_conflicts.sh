#!/bin/bash
set -e
source dev-container-features-test-lib

# Create a conflict
touch "$HOME/.vimrc"
echo "original" > "$HOME/.vimrc"

# Config to overwrite
mkdir -p "$HOME/dotfiles"
echo "new" > "$HOME/dotfiles/.vimrc"
echo '{"files": [{"source": "~/dotfiles/.vimrc", "target": "~/.vimrc"}]}' > "$HOME/.devcontainer.profile"

/usr/local/share/devcontainer-profile/scripts/apply.sh

check "files: symlink created" [ -L "$HOME/.vimrc" ]
check "files: backup created" [ -f "$HOME/.vimrc.bak" ]
check "files: backup content preserved" grep "original" "$HOME/.vimrc.bak"

reportResults