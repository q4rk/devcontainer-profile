#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Setup the challenging config
mkdir -p "$HOME/.devcontainer-profile"
cat << EOF > "$HOME/.devcontainer-profile/config.json"
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
    "github.com/jesseduffield/lazygit"
  ],
  "cargo": [
    "lsd",
    "du-dust"
  ],
  "features": [
    { "id": "ghcr.io/devcontainers/features/aws-cli:1" },
    { "id": "ghcr.io/devcontainers/features/terraform:1" },
    { "id": "ghcr.io/devcontainers/features/rust:1" }
  ],
  "scripts": [
    "echo 'alias please="sudo"' >> ~/.bashrc",
    "echo 'alias ll="lsd -la"' >> ~/.bashrc",
    "fortune | cowsay | lolcat > ~/welcome_message.txt",
    "echo 'cat ~/welcome_message.txt' >> ~/.bashrc"
  ]
}
EOF

# Trigger apply
# Note: In a real test environment, many of these tools won't actually install 
# unless we have the full internet and all compilers, but we can check if the 
# engine attempts to install them or if it crashes.
sudo /usr/local/share/devcontainer-profile/scripts/apply.sh

# Verifications
check "scripts: welcome message created" [ -f "$HOME/welcome_message.txt" ]
check "bashrc: aliases added" grep "alias please" "$HOME/.bashrc"

# Check if the engine survived the complex JSON structure
check "engine: survived challenging config" [ -f "/var/tmp/devcontainer-profile/state/last_applied_hash" ]

reportResults
