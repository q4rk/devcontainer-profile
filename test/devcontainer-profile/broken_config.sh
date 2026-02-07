#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Inject invalid JSON
mkdir -p "$HOME/.devcontainer-profile"
echo '{ "invalid": "json", [broken] }' > "$HOME/.devcontainer-profile/config.json"

# Trigger apply - it should NOT exit with non-zero
if sudo /usr/local/share/devcontainer-profile/scripts/apply.sh; then
    check "engine: survived broken config" true
else
    check "engine: failed on broken config (expected survival)" false
fi

# Verify it didn't do anything crazy but the log shows issues
check "log: captures errors" grep -i "error" /var/tmp/devcontainer-profile/state/devcontainer-profile.log

reportResults
