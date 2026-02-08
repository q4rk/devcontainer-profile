#!/bin/bash
set -e
source dev-container-features-test-lib

echo ">>> Scenario: Root User"

# Ensure logs are printed on exit (success or failure)
show_logs() {
    echo ">>> Final Profile Log:"
    cat /var/tmp/devcontainer-profile/state/profile.log 2>/dev/null || echo "(Log file empty or missing)"
}
trap show_logs EXIT

check "Running as root" [ "$(id -u)" -eq 0 ]

mkdir -p "/root/.devcontainer.profile"
echo '{"env": {"ROOT_TEST": "1"}}' > "/root/.devcontainer.profile/config.json"

/usr/local/share/devcontainer-profile/scripts/apply.sh

source "/root/.devcontainer.profile_env"
check "Root env applied" [ "$ROOT_TEST" == "1" ]

reportResults
