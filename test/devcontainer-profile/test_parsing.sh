#!/bin/bash
source /tmp/test_lib.sh

setup_suite
mock_utils
setup_mocks

echo "=== Config Parsing & Command Mapping Tests ==="

# 1. Setup Complex Configuration
cat << 'EOF' > "$USER_CONFIG_PATH"
{
  "apt": [
    "basic-pkg", 
    { "name": "versioned-pkg", "version": "1.0" }
  ],
  "pip": {
    "bin": "pip3",
    "packages": ["black", "mypy==1.0"]
  },
  "npm": ["typescript@next"],
  "go": ["golang.org/x/tools/gopls@latest"],
  "cargo": ["ripgrep"],
  "vscode-extensions": ["ms-python.python"],
  "features": [
    { "id": "ghcr.io/devcontainers/features/github-cli:1", "options": { "version": "2.0" } }
  ]
}
EOF

# 2. Run Plugins (simulate the loop in apply.sh)
for plugin in "$PLUGIN_DIR"/*.sh; do
    echo "Running: $(basename "$plugin")"
    source "$plugin" >/dev/null 2>&1 || true
done

# 3. Verify Audits
echo "--- Verifying Output ---"

# APT: Note that the logic aggregates packages
assert_audit "apt-get install -y --no-install-recommends basic-pkg versioned-pkg=1.0"

# PIP: Verify binary substitution and user flag
assert_audit "pip3 install --user --upgrade black mypy==1.0"

# NPM: Verify global flag
assert_audit "npm install -g typescript@next"

# GO: Verify install command
assert_audit "go install golang.org/x/tools/gopls@latest"

# CARGO: Verify install command
assert_audit "cargo install ripgrep"

# VSCODE: Verify force install
assert_audit "code --install-extension ms-python.python --force"

# FEATURES: Verify feature-installer arguments
assert_audit "feature-installer feature install ghcr.io/devcontainers/features/github-cli:1 --option version=2.0"

echo "All parsing logic confirmed."