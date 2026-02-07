#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup a complex config using the discovery file (~/.devcontainer.profile)
# This ensures it survives the engine's symlink creation.
cat << EOF > "$HOME/.devcontainer.profile"
{
    "apt": ["sl"],
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

# Run the engine as the current user. 
# It will use sudo internally for apt-get.
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "apt: sl is installed" command -v sl
check "env: variable is set" grep "SCENARIO_TEST" "$HOME/.devcontainer.profile_env"
check "files: symlink created" [ -L "$HOME/test_target" ]
check "scripts: executed" [ -f "$HOME/script_success" ]

# Test Idempotency: Run again
check "idempotency: run again" /usr/local/share/devcontainer-profile/scripts/apply.sh

reportResults
