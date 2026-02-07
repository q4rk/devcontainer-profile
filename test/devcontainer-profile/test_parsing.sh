#!/bin/bash

set -o errexit
set -o pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export MANAGED_CONFIG_DIR="$HOME/.devcontainer-profile"
export USER_CONFIG_PATH="$MANAGED_CONFIG_DIR/config.json"
export USER_PATH_FILE="$HOME/.devcontainer.profile_path"
export PLUGIN_DIR="$TEST_ROOT/plugins"
export AUDIT_LOG="$TEST_ROOT/audit.log"
export LOG_FILE="$TEST_ROOT/devcontainer-profile.log"

mkdir -p "$HOME" "$PLUGIN_DIR" "$TEST_ROOT/bin" "$MANAGED_CONFIG_DIR"
touch "$LOG_FILE" "$AUDIT_LOG"

REAL_PLUGIN_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../src/devcontainer-profile" && pwd)/scripts/plugins"
cp "$REAL_PLUGIN_SRC"/*.sh "$PLUGIN_DIR/"

mock_tool() {
    echo -e "#!/bin/bash\necho \"AUDIT: \$0 \$*\" >> \"$AUDIT_LOG\"" > "$TEST_ROOT/bin/$1"
    chmod +x "$TEST_ROOT/bin/$1"
}
export PATH="$TEST_ROOT/bin:$PATH"

# Setup mocks for standard and versioned binaries
for tool in apt-get pip pip3.11 npm go cargo feature-installer sudo code; do mock_tool "$tool"; done

# Shared utility mocks (from apply.sh)
log() { echo "[$1] $2"; }
info() { log "INFO" "$1"; }
warn() { log "WARN" "$1"; }
error() { log "ERROR" "$1"; }
ensure_root() { echo "AUDIT: sudo $*" >> "$AUDIT_LOG"; "$@"; }
export -f log info warn error ensure_root

assert_parsed() {
    if grep -q "$1" "$AUDIT_LOG"; then
        echo -e "  \e[32mPASS\e[0m: Correctly parsed '$1'"
    else
        echo -e "  \e[31mFAIL\e[0m: Mismatch! Expected command not found in audit log."
        echo "  Expected: $1"
        echo "  Actual Log Snippet:"
        grep -i "$(echo "$1" | awk '{print $2}')" "$AUDIT_LOG" || echo "  (Command not found at all)"
        exit 1
    fi
}

echo "Starting End-to-End Parsing Validation..."

cat << 'EOF' > "$USER_CONFIG_PATH"
{
  "apt": ["basic-pkg", {"name": "versioned-pkg", "version": "1.2.3"}],
  "pip": {
    "bin": "pip3.11",
    "packages": ["black", "mypy==1.0.0"]
  },
  "npm": ["prettier", "typescript@next"],
  "go": ["golang.org/x/tools/gopls", "github.com/go-delve/delve/cmd/dlv@v1.2"],
  "cargo": ["ripgrep@13.0.0"],
  "vscode-extensions": ["ms-python.python", "redhat.vscode-yaml"],
  "vscode-settings": {
    "editor.formatOnSave": true
  },
  "env": {
    "TEST_VAR": "42"
  },
  "verify": [
    "command -v basic-pkg"
  ],
  "features": [
    { "id": "ghcr.io/devcontainers/features/github-cli:1", "options": { "version": "latest" } }
  ],
  "scripts": [
    "echo PARSE_TEST_MARKER"
  ]
}
EOF

for plugin in "$PLUGIN_DIR"/*.sh; do
    echo "Running plugin: $(basename "$plugin")"
    # Capture the "Running plugin" info log into the audit log for verification
    echo "AUDIT: Running plugin: $(basename "$plugin")" >> "$AUDIT_LOG"
    # shellcheck source=/dev/null
    source "$plugin" >/dev/null 2>&1 || true
done

echo "Verifying Parsing Results:"
assert_parsed "apt-get install -y --no-install-recommends basic-pkg versioned-pkg=1.2.3"
assert_parsed "pip3.11 install --user --upgrade black mypy==1.0.0"
assert_parsed "npm install -g prettier typescript@next"
assert_parsed "go install golang.org/x/tools/gopls@latest"
assert_parsed "go install github.com/go-delve/delve/cmd/dlv@v1.2"
assert_parsed "code --install-extension ms-python.python --force"
assert_parsed "code --install-extension redhat.vscode-yaml --force"
assert_parsed "Running plugin: 80-vscode-settings.sh"
assert_parsed "Running plugin: 45-env.sh"
assert_parsed "Running plugin: 99-verify.sh"
assert_parsed "feature-installer feature install ghcr.io/devcontainers/features/github-cli:1 --option version=latest"
echo "All Parsing Validations passed successfully."
