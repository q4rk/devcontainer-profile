#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Verify identity
info "Current user: $(id)"
check "user: is root" [ "$(id -u)" -eq 0 ]

# Config for root via discovery file
echo '{"env": {"ROOT_ACTIVE": "true"}}' > "$HOME/.devcontainer.profile"

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "engine: link established" [ -L "$HOME/.devcontainer-profile" ]
check "env: variable set for root" grep "ROOT_ACTIVE" "$HOME/.devcontainer.profile_env"

reportResults
