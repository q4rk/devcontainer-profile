#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

info() { echo "INFO: $*"; }

# Prepare environment: ensure Zsh config exists as well
touch "$HOME/.bashrc" "$HOME/.zshrc"

# 1. Setup initial config
cat << EOF > "$HOME/.devcontainer.profile"
{
  "env": {
    "DUPLICATE_TEST": "true"
  },
  "apt": ["cowsay"],
  "shell-history": true,
  "scripts": [
    "grep -q 'alias duplicate_check=' ~/.bashrc || echo 'alias duplicate_check=\"echo works\"' >> ~/.bashrc"
  ]
}
EOF

# 2. First Run
info "Execution #1: Initial application..."
/usr/local/share/devcontainer-profile/scripts/apply.sh

# 3. Second Run (Idempotency - No config change)
info "Execution #2: Sequential application (same hash)..."
/usr/local/share/devcontainer-profile/scripts/apply.sh

# 4. Third Run (Simulated "Feature Instance 2" - same hash)
# We remove the marker but keep the hash to test if it detects 'applied' state correctly
# or if it re-applies cleanly.
rm -f "$HOME/.devcontainer-profile.applied"
info "Execution #3: Marker removed, re-applying (should detect hash match)..."
/usr/local/share/devcontainer-profile/scripts/apply.sh

# 5. Verifications for Sequential Stability
check "bashrc: PATH source block is unique" [ $(grep -c ".devcontainer.profile_path" "$HOME/.bashrc") -eq 1 ]
check "zshrc: PATH source block is unique" [ $(grep -c ".devcontainer.profile_path" "$HOME/.zshrc") -eq 1 ]
check "bashrc: ENV source block is unique" [ $(grep -c ".devcontainer.profile_env" "$HOME/.bashrc") -eq 1 ]
check "bashrc: History source block is unique" [ $(grep -c "shell-history" "$HOME/.bashrc") -eq 1 ]
check "bashrc: Script-added alias is unique" [ $(grep -c "alias duplicate_check" "$HOME/.bashrc") -eq 1 ]

# 6. Modification Run (Hash change)
info "Execution #4: Modifying config (hash change)..."
cat << EOF > "$HOME/.devcontainer.profile"
{
  "env": {
    "DUPLICATE_TEST": "updated",
    "NEW_VAR": "added"
  },
  "apt": ["cowsay"],
  "shell-history": true
}
EOF
/usr/local/share/devcontainer-profile/scripts/apply.sh

# 7. Verifications after update
check "env: file exists" [ -f "$HOME/.devcontainer.profile_env" ]
check "env: DUPLICATE_TEST updated" grep "DUPLICATE_TEST=\"updated\"" "$HOME/.devcontainer.profile_env"
check "env: NEW_VAR added" grep "NEW_VAR=\"added\"" "$HOME/.devcontainer.profile_env"

# Critical: Even after a hash change and re-run, injection blocks should still be unique
check "bashrc: PATH source block remains unique" [ $(grep -c ".devcontainer.profile_path" "$HOME/.bashrc") -eq 1 ]
check "zshrc: PATH source block remains unique" [ $(grep -c ".devcontainer.profile_path" "$HOME/.zshrc") -eq 1 ]
check "bashrc: ENV source block remains unique" [ $(grep -c ".devcontainer.profile_env" "$HOME/.bashrc") -eq 1 ]

# 8. Path Persistence Stability
# Add a custom bin to PATH and verify it doesn't duplicate in the persistence file
mkdir -p "$HOME/custom_bin"
export PATH="$PATH:$HOME/custom_bin"
/usr/local/share/devcontainer-profile/scripts/apply.sh
if [ -f "$HOME/.devcontainer.profile_path" ]; then
    check "path: persistence file has no duplicate lines" [ $(sort "$HOME/.devcontainer.profile_path" | uniq -d | wc -l) -eq 0 ]
fi

# 9. Symlink Health
check "core: managed config is a symlink" [ -L "$HOME/.devcontainer-profile" ]
check "core: symlink points to volume" [ "$(readlink "$HOME/.devcontainer-profile")" = "/var/tmp/devcontainer-profile/state/configs" ]

reportResults
