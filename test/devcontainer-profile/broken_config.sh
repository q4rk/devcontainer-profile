#!/bin/bash
set -e
source dev-container-features-test-lib

# 1. Setup invalid JSON
# We use a mocked discovery path
CONFIG_DIR="$HOME/.config/devcontainer-profile"
mkdir -p "$CONFIG_DIR"
echo '{ "invalid": "json", [broken_array] }' > "$CONFIG_DIR/config.json"

# 2. Run Engine
# It should NOT exit with error code (fail-soft philosophy), but it should log errors
echo "Running engine with broken config..."
if /usr/local/share/devcontainer-profile/scripts/apply.sh; then
    check "engine: exit code 0 on bad config" true
else
    check "engine: exit code 0 on bad config" false
fi

# 3. Verify Log
LOG_FILE="/var/tmp/devcontainer-profile/state/devcontainer-profile.log"
check "log: exists" [ -f "$LOG_FILE" ]

# Check for jq errors or internal warnings
if grep -Eiq "(parse error|jq:|failed)" "$LOG_FILE"; then
    check "log: recorded parsing error" true
else
    echo "Dumping Log:"
    cat "$LOG_FILE"
    check "log: recorded parsing error" false
fi

reportResults