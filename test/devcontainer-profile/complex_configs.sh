#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup a complex config
CONFIG_DIR="$HOME/.devcontainer-profile"
mkdir -p "$CONFIG_DIR"
cat << EOF > "$CONFIG_DIR/config.json"
{
    "apt": ["tree"],
    "env": {
        "SCENARIO_TEST": "battle-tested"
    },
    "files": [
        { "source": "~/test_source", "target": "~/test_target" }
    ],
    "scripts": [
        "touch ~/script_success"
    ]
}
EOF

# Create a source file for the symlink test
touch "$HOME/test_source"

# Manually trigger apply.sh to process our new config
# We use sudo because apply.sh might need to run apt-get
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "apt: tree is installed" command -v tree
check "env: variable is set" grep "SCENARIO_TEST" "$HOME/.devcontainer.profile_env"
check "files: symlink created" ls "$HOME/test_target"
check "scripts: executed" ls "$HOME/script_success"

# Test Idempotency: Run again, should be fast and no errors
check "idempotency: run again" sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

reportResults
