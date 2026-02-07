#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup conflict: a real file exists where we want a symlink
echo "pre-existing content" > "$HOME/.bash_aliases"

# Config to link a new file there (via discovery file)
mkdir -p "$HOME/my_dotfiles"
echo "alias gs='git status'" > "$HOME/my_dotfiles/.bash_aliases"

cat << EOF > "$HOME/.devcontainer.profile"
{
    "files": [
        { "source": "~/my_dotfiles/.bash_aliases", "target": "~/.bash_aliases" }
    ]
}
EOF

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
if [ -L "$HOME/.bash_aliases" ]; then
    check "files: symlink created despite conflict" true
else
    echo "(!) DEBUG: Log output follows:"
    cat /var/tmp/devcontainer-profile/state/devcontainer-profile.log
    check "files: symlink created despite conflict" false
fi

check "files: original file backed up" [ -f "$HOME/.bash_aliases.bak" ]
check "files: backup content preserved" grep "pre-existing content" "$HOME/.bash_aliases.bak"

reportResults
