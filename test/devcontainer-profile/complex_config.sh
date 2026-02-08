#!/bin/bash
set -e
source dev-container-features-test-lib

echo ">>> Scenario: Complex Configuration"

# Ensure logs are printed on exit (success or failure)
show_logs() {
    echo ">>> Final Profile Log:"
    cat /var/tmp/devcontainer-profile/state/profile.log 2>/dev/null || echo "(Log file empty or missing)"
}
trap show_logs EXIT

# Setup: Create a config that uses multiple features
rm -rf "$HOME/.devcontainer.profile"
mkdir -p "$HOME/.devcontainer.profile"
cat <<EOF > "$HOME/.devcontainer.profile/config.json"
{
    "apt": ["sl"],
    "env": { "SCENARIO_TEST": "TRUE" },
    "scripts": ["touch $HOME/script_ran"]
}
EOF

# Run Engine
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Sourcing required for PATH and Env
[ -f "$HOME/.devcontainer.profile_path" ] && . "$HOME/.devcontainer.profile_path"
[ -f "$HOME/.devcontainer.profile_env" ] && . "$HOME/.devcontainer.profile_env"

# Verify APT
check "APT installed 'sl'" command -v sl

# Verify Env (Sourcing required)
source "$HOME/.devcontainer.profile_env"
check "Env var set" [ "$SCENARIO_TEST" == "TRUE" ]

# Verify Scripts
check "Script executed" test -f "$HOME/script_ran"

reportResults
