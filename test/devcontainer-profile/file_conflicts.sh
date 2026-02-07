#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup conflict: a real file exists where we want a symlink
echo "pre-existing content" > "$HOME/.bash_aliases"

# Config to link a new file there
mkdir -p "$HOME/my_dotfiles"
echo "alias gs='git status'" > "$HOME/my_dotfiles/.bash_aliases"
mkdir -p "$HOME/.devcontainer-profile"
cat << EOF > "$HOME/.devcontainer-profile/config.json"
{
    "files": [
        { "source": "~/my_dotfiles/.bash_aliases", "target": "~/.bash_aliases" }
    ]
}
EOF

# Trigger apply
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "files: symlink created despite conflict" [ -L "$HOME/.bash_aliases" ]
check "files: original file backed up" [ -f "$HOME/.bash_aliases.bak" ]
check "files: backup content preserved" grep "pre-existing content" "$HOME/.bash_aliases.bak"

reportResults
