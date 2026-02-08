#!/bin/bash
set -e
source dev-container-features-test-lib

echo '{"env": {"IDEMPOTENCY": "1"}}' > "$HOME/.devcontainer.profile"

# Run 1
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Run 2
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Count occurrences in bashrc. Should be 1.
COUNT=$(grep -c ".devcontainer.profile_env" "$HOME/.bashrc")

check "bashrc: source line is unique" [ "$COUNT" -eq 1 ]

reportResults