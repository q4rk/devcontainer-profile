#!/bin/bash
set -o errexit
set -o pipefail

source "$(dirname "$0")/test_utils.sh"
setup_hermetic_env

cleanup() {
    echo ">>> Final Profile Log: unit plugin test"
    cat "$LOG_FILE" 2>/dev/null || echo "(Log file empty or missing)"
    teardown_hermetic_env
}
trap cleanup EXIT

echo "=== [Unit] Plugin Integration Tests ==="

# Mock the entire toolchain
for tool in sudo apt-get pip pip3 npm go cargo code feature-installer git; do
    mock_tool "$tool"
done

# Scenario: The Kitchen Sink Config
# We write a complex config and verify the specific commands generated.
cat <<EOF > "$USER_CONFIG_PATH"
{
  "apt": [
    "simple-tool", 
    { "name": "complex-tool", "version": "1.0" }
  ],
  "pip": ["black==20.0"],
  "npm": ["prettier"],
  "go": ["gopls@latest"],
  "cargo": ["ripgrep"],
  "vscode-extensions": ["ms-python.python"],
  "scripts": ["echo 'custom script running'"],
  "files": [
    { "source": "$HOME/dotfiles/.vimrc", "target": "~/.vimrc" }
  ]
}
EOF

# Setup Dotfiles source for the file plugin
mkdir -p "$HOME/dotfiles"
touch "$HOME/dotfiles/.vimrc"

# Run the Engine
"$INSTALL_DIR/scripts/apply.sh"

echo "--- Verifying APT ---"
# Expect: apt-get install -y ... simple-tool complex-tool=1.0
assert_audit_call "apt-get" 'any(. == "simple-tool") and any(. == "complex-tool=1.0")'

echo "--- Verifying Languages ---"
assert_audit_call "pip" 'contains(["install", "black==20.0"])'
assert_audit_call "npm" 'contains(["install", "-g", "prettier"])'
assert_audit_call "go" 'contains(["install", "gopls@latest"])'
assert_audit_call "cargo" 'contains(["install", "ripgrep"])'

echo "--- Verifying VS Code ---"
assert_audit_call "code" 'contains(["--install-extension", "ms-python.python"])'

echo "--- Verifying Files ---"
assert_file_exists "$HOME/.vimrc"
if [[ -L "$HOME/.vimrc" ]]; then
    log_pass "Symlink created"
else
    log_fail "File is not a symlink"
fi

echo "=== Plugin Tests Passed ==="
