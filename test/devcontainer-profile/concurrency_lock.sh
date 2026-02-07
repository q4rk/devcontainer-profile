#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Launch instances in the background
for i in {1..5}; do
    ( /usr/local/share/devcontainer-profile/scripts/apply.sh ) &
done
wait

# Check if the lock file exists
check "engine: lock exists" [ -f "/var/tmp/devcontainer-profile/state/devcontainer-profile.lock" ]

reportResults
