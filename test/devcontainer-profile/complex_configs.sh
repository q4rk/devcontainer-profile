#!/bin/bash
set -e
source dev-container-features-test-lib

# Test object-based configuration for languages
cat << EOF > "$HOME/.devcontainer.profile"
{
    "pip": {
        "bin": "pip",
        "packages": ["requests"]
    },
    "npm": {
        "bin": "npm",
        "packages": ["ts-node"]
    }
}
EOF

/usr/local/share/devcontainer-profile/scripts/apply.sh

# Reload path to ensure we pick up shimmed binaries if any
[ -f "$HOME/.devcontainer.profile_path" ] && . "$HOME/.devcontainer.profile_path"

# We check if the pip module is actually installed
if python3 -m pip show requests > /dev/null 2>&1 || pip show requests > /dev/null 2>&1; then
    check "pip: requests installed" true
else
    check "pip: requests installed" false
fi

check "npm: ts-node installed" command -v ts-node

reportResults