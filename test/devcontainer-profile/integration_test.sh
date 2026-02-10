#!/bin/bash
set -e
source dev-container-features-test-lib

echo ">>> Scenario: Integration Test"

# Ensure logs are printed on exit (success or failure)
show_logs() {
    echo ">>> Final Profile Log: Integration Test"
    cat /var/tmp/devcontainer-profile/state/profile.log 2>/dev/null || echo "(Log file empty or missing)"
}
trap show_logs EXIT

# Create source file for the files plugin BEFORE running engine
mkdir -p "$HOME"
echo "test content" > "$HOME/test_source"

# Create the directory first as it's now our managed path
rm -rf "$HOME/.devcontainer.profile"
mkdir -p "$HOME/.devcontainer.profile"
cat << EOF > "$HOME/.devcontainer.profile/config.json"
{
  "apt": [
    "cowsay",
    "fortune-mod",
    "fortunes",
    "fortunes-min",
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
  "gem": [
    "lolcat"
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
    {"id": "ghcr.io/devcontainers/features/rust:1"},
    {"id": "ghcr.io/devcontainers/features/ruby:1"}
  ],
  "scripts": [
    "grep -q 'alias please' ~/.bashrc || echo 'alias please=\"sudo\"' >> ~/.bashrc",
    "grep -q 'alias ll' ~/.bashrc || echo 'alias ll=\"lsd -la\"' >> ~/.bashrc",
    "fortune | cowsay | lolcat > ~/welcome_message.txt",
    "grep -q 'welcome_message.txt' ~/.bashrc || echo 'cat ~/welcome_message.txt' >> ~/.bashrc",
    "touch ~/script_success.txt"
  ],
  "files": [
        { "source": "~/test_source", "target": "~/test_target" }
    ],
  "env": {
        "SCENARIO_TEST": "battle-tested"
    }
}
EOF

/usr/local/share/devcontainer-profile/scripts/apply.sh

[ -f "$HOME/.devcontainer.profile_path" ] && . "$HOME/.devcontainer.profile_path"
[ -f "$HOME/.devcontainer.profile_env" ] && . "$HOME/.devcontainer.profile_env"

check "apt: cowsay" command -v cowsay
check "pip: thefuck" command -v thefuck
check "npm: chalk" command -v chalk
check "npm: localtunnel" command -v lt
check "gem: lolcat" command -v lolcat
check "files: script success" [ -f "$HOME/script_success.txt" ]
check "go: lazygit is installed" command -v lazygit
check "cargo: dust is installed" command -v dust
check "scripts: welcome message created" [ -f "$HOME/welcome_message.txt" ]
check "bashrc: aliases added" grep "alias please" "$HOME/.bashrc"
check "env: variable is set" grep "SCENARIO_TEST" "$HOME/.devcontainer.profile_env"
check "files: symlink created" [ -L "$HOME/test_target" ]

# Write Test: Ensure user can write a new config to the managed directory
echo '{"new": "config"}' > "$HOME/.devcontainer.profile/test_write.json"
check "managed dir is writable" [ -f "$HOME/.devcontainer.profile/test_write.json" ]
check "managed dir persistence" [ -f "/var/tmp/devcontainer-profile/state/configs/test_write.json" ]

reportResults
