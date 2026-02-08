#!/bin/bash
set -e
source dev-container-features-test-lib

LOCK_FILE="/var/tmp/devcontainer-profile/state/devcontainer-profile.lock"

# 1. Create a fake lock
mkdir -p "$(dirname "$LOCK_FILE")"
# Lock it using flock in background to simulate another process
exec 200>"$LOCK_FILE"
flock -n 200

# 2. Run engine in background
(/usr/local/share/devcontainer-profile/scripts/apply.sh) &
PID=$!

# 3. Verify it is waiting (grep process list or check log)
sleep 1
if ps -p $PID > /dev/null; then
    check "engine: waits on lock" true
else
    check "engine: waits on lock" false
fi

# 4. Release lock
flock -u 200
wait $PID

check "engine: finished after lock release" true

reportResults