#!/bin/bash
set -e
source dev-container-features-test-lib

# 1. Complex Configuration
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
    { "id": "ghcr.io/devcontainers/features/terraform:1" },
    {"id": "ghcr.io/devcontainers/features/rust:1"}
  ],
  "scripts": [
    "grep -q 'alias please' ~/.bashrc || echo 'alias please=\"sudo\"' >> ~/.bashrc",
    "grep -q 'alias ll' ~/.bashrc || echo 'alias ll=\"lsd -la\"' >> ~/.bashrc",
    "fortune | cowsay | lolcat > ~/welcome_message.txt",
    "grep -q 'welcome_message.txt' ~/.bashrc || echo 'cat ~/welcome_message.txt' >> ~/.bashrc"
  ],
  "files": [
        { "source": "~/test_source", "target": "~/test_target" }
    ],
  "env": {
        "SCENARIO_TEST": "battle-tested"
    },
}
EOF

# 2. Execute
/usr/local/share/devcontainer-profile/scripts/apply.sh

# 3. Source environment
[ -f "$HOME/.devcontainer.profile_path" ] && . "$HOME/.devcontainer.profile_path"
[ -f "$HOME/.devcontainer.profile_env" ] && . "$HOME/.devcontainer.profile_env"

# 4. Assertions
check "apt: cowsay" command -v cowsay
check "pip: thefuck" command -v thefuck
check "npm: chalk" command -v chalk
check "env: variable set" [ "$STRESS_TEST" == "true" ]
check "files: backup created" [ -L "$HOME/hosts_backup" ]
check "go: lazygit is installed" command -v lazygit
check "cargo: lsd is installed" command -v lsd
check "scripts: welcome message created" [ -f "$HOME/welcome_message.txt" ]
check "bashrc: aliases added" grep "alias please" "$HOME/.bashrc"
check "env: variable is set" grep "SCENARIO_TEST" "$HOME/.devcontainer.profile_env"
check "files: symlink created" [ -L "$HOME/test_target" ]

reportResults