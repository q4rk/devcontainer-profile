#!/bin/bash
set -e
source dev-container-features-test-lib

cat << 'EOF' > "$HOME/.devcontainer.profile"
{
    "env": {
        "TRICKY": "Spaces 'Quotes' & Ampersands",
        "EMOJI": "🚀"
    }
}
EOF

/usr/local/share/devcontainer-profile/scripts/apply.sh

source "$HOME/.devcontainer.profile_env"

check "env: spaces preserved" [ "$TRICKY" == "Spaces 'Quotes' & Ampersands" ]
check "env: emoji preserved" [ "$EMOJI" == "🚀" ]

reportResults