#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup the challenging config using discovery file
cat << EOF > "$HOME/.devcontainer.profile"
{
  "apt": ["sl", "cowsay"],
  "scripts": [
    "echo 'alias please=\"sudo\"' >> ~/.bashrc",
    "touch ~/challenging_success"
  ]
}
EOF

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "scripts: executed" [ -f "$HOME/challenging_success" ]
check "bashrc: aliases added" grep "alias please" "$HOME/.bashrc"

reportResults
