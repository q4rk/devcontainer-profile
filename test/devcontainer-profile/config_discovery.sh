#!/bin/bash
set -e
source dev-container-features-test-lib

# Simulate XDG Config mount
XDG_DIR="$HOME/.config/devcontainer-profile"
mkdir -p "$XDG_DIR"
echo '{"env": {"XDG_FOUND": "1"}}' > "$XDG_DIR/config.json"

/usr/local/share/devcontainer-profile/scripts/apply.sh

check "discovery: found XDG config" grep "XDG_FOUND" "$HOME/.devcontainer.profile_env"

reportResults