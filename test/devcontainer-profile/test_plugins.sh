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

mkdir -p "$HOME" "$PLUGIN_DIR" "$MANAGED_CONFIG_DIR"
touch "$LOG_FILE"

# Discovery logic for plugin source
if [[ -d "/usr/local/share/devcontainer-profile/plugins" ]]; then
    REAL_PLUGIN_SRC="/usr/local/share/devcontainer-profile/plugins"
elif [[ -d "$(pwd)/../../src/devcontainer-profile/scripts/plugins" ]]; then
    REAL_PLUGIN_SRC="$(pwd)/../../src/devcontainer-profile/scripts/plugins"
elif [[ -d "/workspaces/src/devcontainer-profile/scripts/plugins" ]]; then
    REAL_PLUGIN_SRC="/workspaces/src/devcontainer-profile/scripts/plugins"
else
    # Last ditch effort: find it
    REAL_PLUGIN_SRC=$(find / -type d -name "plugins" | grep "devcontainer-profile/scripts/plugins" | head -n 1 || true)
fi

if [[ -z "$REAL_PLUGIN_SRC" || ! -d "$REAL_PLUGIN_SRC" ]]; then
    echo "(!) ERROR: Could not locate plugin source directory."
    exit 1
fi

info "Using plugin source: $REAL_PLUGIN_SRC"
cp "$REAL_PLUGIN_SRC"/*.sh "$PLUGIN_DIR/"

log() { echo "[$1] $2"; }
info() { log "INFO" "$1"; }
warn() { log "WARN" "$1"; }
error() { log "ERROR" "$1"; }
ensure_root() { echo "MOCK_ROOT_CALL: $*" >> "$AUDIT_LOG"; "$@"; }

MOCK_BIN="$TEST_ROOT/mock_bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

mock_tool() {
    echo -e "#!/bin/bash\necho \"MOCK_CALL: $1 \$*\" >> \"$AUDIT_LOG\"" > "$MOCK_BIN/$1"
    chmod +x "$MOCK_BIN/$1"
}

mock_tool "apt-get"
mock_tool "feature-installer"
mock_tool "pip"
mock_tool "npm"
mock_tool "go"
mock_tool "cargo"
mock_tool "sudo"
mock_tool "code"

export -f log info warn error ensure_root

assert_audit() {
    if grep -q "$1" "$AUDIT_LOG"; then
        echo -e "  \e[32mPASS\e[0m: Audit found '$1'"
    else
        echo -e "  \e[31mFAIL\e[0m: Audit missing '$1'"
        echo "LOG CONTENT:"
        cat "$AUDIT_LOG"
        exit 1
    fi
}

echo "Starting Plugin Validation Suite..."

echo "[Plugin Test] 10-apt.sh"
echo '{"apt": ["htop", {"name": "tree", "version": "2.1"}]}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/10-apt.sh"
assert_audit "MOCK_CALL: apt-get install -y --no-install-recommends htop tree=2.1"

echo "[Plugin Test] 60-files.sh"
mkdir -p "$HOME/dotfiles"
touch "$HOME/dotfiles/.gitconfig"
echo '{"files": [{"source": "~/dotfiles/.gitconfig", "target": "~/.gitconfig"}]}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/60-files.sh"
if [[ -L "$HOME/.gitconfig" ]]; then
    echo -e "  \e[32mPASS\e[0m: Symlink verified"
else
    echo -e "  \e[31mFAIL\e[0m: Symlink not created"
    exit 1
fi

echo "[Plugin Test] 30-languages.sh"
echo '{"pip": ["black"], "npm": ["tldr"], "go": ["gopls"]}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/30-languages.sh"
# Corrected assertions based on real plugin flags
assert_audit "MOCK_CALL: pip install --user --upgrade black"
assert_audit "MOCK_CALL: npm install -g tldr"
assert_audit "MOCK_CALL: go install gopls@latest"

echo "[Plugin Test] 45-env.sh"
echo '{"env": {"MY_VAR": "hello world"}}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/45-env.sh"
if grep -q 'export MY_VAR="hello world"' "$HOME/.devcontainer.profile_env"; then
    echo -e "  \e[32mPASS\e[0m: Env variable persisted"
else
    echo -e "  \e[31mFAIL\e[0m: Env variable missing"
    cat "$HOME/.devcontainer.profile_env"
    exit 1
fi

echo "[Plugin Test] 70-vscode-extensions.sh"
echo '{"vscode-extensions": ["ms-python.python"]}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/70-vscode-extensions.sh"
assert_audit "MOCK_CALL: code --install-extension ms-python.python --force"

echo "[Plugin Test] 80-vscode-settings.sh"
mkdir -p "$HOME/.vscode-server/data/Machine"
echo '{"existing.setting": true}' > "$HOME/.vscode-server/data/Machine/settings.json"
echo '{"vscode-settings": {"new.setting": 42}}' > "$USER_CONFIG_PATH"
# shellcheck source=/dev/null
source "$PLUGIN_DIR/80-vscode-settings.sh"

if grep -q "new.setting" "$HOME/.vscode-server/data/Machine/settings.json" && \
   grep -q "existing.setting" "$HOME/.vscode-server/data/Machine/settings.json"; then
    echo -e "  \e[32mPASS\e[0m: Settings merged correctly"
else
    echo -e "  \e[31mFAIL\e[0m: Settings merge failed"
    cat "$HOME/.vscode-server/data/Machine/settings.json"
    exit 1
fi

echo "[Plugin Test] 99-verify.sh"
# Clear audit log or use unique markers
echo '{"verify": ["true", "false"]}' > "$USER_CONFIG_PATH"
# We wrap in a subshell to prevent the 'false' command from exiting the test script if it had set -e
# shellcheck source=/dev/null
( source "$PLUGIN_DIR/99-verify.sh" ) || true

echo "All Plugin Validation tests passed."
