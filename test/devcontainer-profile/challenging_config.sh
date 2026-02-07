#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

info() { echo "INFO: $*"; }

# Setup the FULL challenging config using discovery file
cat << EOF > "$HOME/.devcontainer.profile"
{
  "apt": [
    "cowsay",
    "fortune-mod",
    "fortunes",
    "fortunes-min",
    "lolcat",
    "sl",
    "figlet",
    {
      "name": "neofetch",
      "version": "*"
    }
  ],
  "pip": {
    "bin": "pip",
    "packages": [
      "glances",
      "thefuck",
      "asciinema"
    ]
  },
  "npm": [
    "emoj",
    "chalk-cli",
    {
      "bin": "npm",
      "packages": [
        "localtunnel"
      ]
    }
  ],
  "go": [
    "github.com/boyter/scc/v3",
    "github.com/jesseduffield/lazygit@latest"
  ],
  "cargo": [
    "lsd",
    "du-dust"
  ],
  "features": [
    { "id": "ghcr.io/devcontainers/features/aws-cli:1" },
    { "id": "ghcr.io/devcontainers/features/terraform:1" }
  ],
  "scripts": [
    "grep -q 'alias please' ~/.bashrc || echo 'alias please=\"sudo\"' >> ~/.bashrc",
    "grep -q 'alias ll' ~/.bashrc || echo 'alias ll=\"lsd -la\"' >> ~/.bashrc",
    "fortune | cowsay | lolcat > ~/welcome_message.txt",
    "grep -q 'welcome_message.txt' ~/.bashrc || echo 'cat ~/welcome_message.txt' >> ~/.bashrc"
  ]
}
EOF

# Discovery diagnostics
ls -la /usr/local/share/devcontainer-profile/scripts/apply.sh
ls -la "$HOME/.devcontainer.profile"

# Trigger apply
/usr/local/share/devcontainer-profile/scripts/apply.sh

# Re-source the path
if [ -f "$HOME/.devcontainer.profile_path" ]; then
    . "$HOME/.devcontainer.profile_path"
fi

# Discovery diagnostics
info "PATH: $PATH"
info "Searching for cowsay..."
find /usr -name cowsay || true

# Verifications
check "apt: cowsay is installed" command -v cowsay
check "pip: thefuck is installed" command -v thefuck
check "npm: localtunnel is installed" command -v lt
check "go: lazygit is installed" command -v lazygit
if ! command -v lsd >/dev/null 2>&1; then
    echo "(!) ERROR: lsd not found in PATH. Diagnostic Log (/var/tmp/devcontainer-profile/state/devcontainer-profile.log):"
    echo "--- FULL LOG ---"
    cat /var/tmp/devcontainer-profile/state/devcontainer-profile.log || true
    echo "--- ALL ERRORS/WARNINGS (Case-Insensitive) ---"
    grep -Ei "error|warn|failed" /var/tmp/devcontainer-profile/state/devcontainer-profile.log || true
fi
check "cargo: lsd is installed" command -v lsd

check "scripts: welcome message created" [ -f "$HOME/welcome_message.txt" ]
check "bashrc: aliases added" grep "alias please" "$HOME/.bashrc"
check "path: cargo bin is in path" grep "cargo/bin" "$HOME/.devcontainer.profile_path"

reportResults
