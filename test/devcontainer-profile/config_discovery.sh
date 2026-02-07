#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Place config in the discovery path (mimicking a bind mount)
DISCOVERY_PATH="/var/tmp/devcontainer-profile/.config/.devcontainer-profile"
mkdir -p "$DISCOVERY_PATH"
echo '{"env": {"DISCOVERED": "true"}}' > "$DISCOVERY_PATH/config.json"

# Clean the volume to force discovery
sudo rm -rf /var/tmp/devcontainer-profile/configs/*

# Trigger apply
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "discovery: config ingested" [ -f "$HOME/.devcontainer-profile/config.json" ]
check "env: variable set from discovered config" grep "DISCOVERED" "$HOME/.devcontainer.profile_env"

reportResults
