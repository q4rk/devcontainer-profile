#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Verify identity
check "user: is root" [ "$(id -u)" -eq 0 ]

# Config for root
mkdir -p "$HOME/.devcontainer-profile"
echo '{"env": {"ROOT_ACTIVE": "true"}}' > "$HOME/.devcontainer-profile/config.json"

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "engine: link established" [ -L "$HOME/.devcontainer-profile" ]
check "env: variable set for root" grep "ROOT_ACTIVE" "$HOME/.devcontainer.profile_env"

reportResults
