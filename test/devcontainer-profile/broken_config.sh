#!/bin/bash
set -e
source dev-container-features-test-lib

echo ">>> Scenario: Broken Configuration (Fail Soft)"

# Ensure logs are printed on exit (success or failure)
show_logs() {
    echo ">>> Final Profile Log: Scenario: Broken Configuration (Fail Soft)"
    cat /var/tmp/devcontainer-profile/state/profile.log 2>/dev/null || echo "(Log file empty or missing)"
}
trap show_logs EXIT

# 1. Inject Invalid JSON
mkdir -p "$HOME/.devcontainer.profile"
echo '{ "invalid": "json", broken_comma, }' > "$HOME/.devcontainer.profile/config.json"

# 2. Run Engine (Should NOT exit 1)
if /usr/local/share/devcontainer-profile/scripts/apply.sh; then
    check "Engine survived invalid JSON" true
else
    check "Engine survived invalid JSON" false
fi

# 3. Verify Log
LOG_FILE="/var/tmp/devcontainer-profile/state/profile.log"
if grep -qi "error" "$LOG_FILE"; then
    check "Errors logged to file" true
else
    check "Errors logged to file" false
fi

reportResults
