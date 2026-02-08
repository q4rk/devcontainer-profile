#!/bin/bash
set -e
source dev-container-features-test-lib

# Only run if we are root
if [ "$(id -u)" -ne 0 ]; then
    echo "Skipping root test (current user: $(id -un))"
    exit 0
fi

echo '{"env": {"ROOT_POWER": "unlimited"}}' > /root/.devcontainer.profile

/usr/local/share/devcontainer-profile/scripts/apply.sh

check "env: root env injected" grep "ROOT_POWER" /root/.devcontainer.profile_env

reportResults