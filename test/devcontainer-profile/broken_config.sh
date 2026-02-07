#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Run once to establish the managed link
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Inject invalid JSON into the managed path
# We use sudo to ensure we can write to the volume-backed directory
sudo bash -c "echo '{ \"invalid\": \"json\", [broken] }' > '$HOME/.devcontainer-profile/config.json'"

# Trigger apply - it should NOT exit with non-zero
if /usr/local/share/devcontainer-profile/scripts/apply.sh; then
    check "engine: survived broken config" true
else
    check "engine: failed on broken config" false
fi

# Verify it didn't do anything crazy but the log shows issues
# We check for either 'error' (from jq/tools) or 'failed' (from our warn helper)
if grep -Ei "error|failed" /var/tmp/devcontainer-profile/state/devcontainer-profile.log; then
    check "log: captures issues" true
else
    check "log: captures issues" false
fi

reportResults
