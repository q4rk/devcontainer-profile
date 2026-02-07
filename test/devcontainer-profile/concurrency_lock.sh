#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Launch 5 instances of the engine in the background
# Each will try to acquire the flock() lock
for i in {1..5}; do
    ( sudo /usr/local/share/devcontainer-profile/scripts/apply.sh ) &
done

# Wait for all background processes
wait

# Verification: The log should show that only one process did the "real" work if the hash was same,
# or more importantly, that no two processes crashed into each other.
# We check the log for "Waiting for lock" messages
if grep -q "Waiting for lock" /var/tmp/devcontainer-profile/state/devcontainer-profile.log; then
    check "engine: concurrency lock verified" true
else
    # If the hash matched quickly, they might not have needed to wait, so we force a change
    echo '{"env": {"C": "1"}}' > "$HOME/.devcontainer-profile/config.json"
    ( sudo /usr/local/share/devcontainer-profile/scripts/apply.sh ) &
    ( sudo /usr/local/share/devcontainer-profile/scripts/apply.sh ) &
    wait
    check "engine: lock exists" [ -f "/var/tmp/devcontainer-profile/state/devcontainer-profile.lock" ]
fi

reportResults
