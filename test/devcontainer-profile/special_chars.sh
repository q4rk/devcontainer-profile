#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Config with complex strings
cat << EOF > "$HOME/.devcontainer.profile"
{
    "env": {
        "COMPLEX_VAR": "Space and 'quotes' and 🚀 emoji",
        "PATH_WITH_SPACE": "/tmp/my space"
    }
}
EOF

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "env: handles spaces and emojis" grep "Space and 'quotes' and 🚀 emoji" "$HOME/.devcontainer.profile_env"

# Verify we can source it
# shellcheck source=/dev/null
source "$HOME/.devcontainer.profile_env"
check "env: sourced correctly" [ "$COMPLEX_VAR" = "Space and 'quotes' and 🚀 emoji" ]

reportResults
