#!/bin/bash
source /tmp/test_lib.sh

setup_suite
mock_utils
setup_mocks

echo "=== Plugin Side-Effect Tests ==="

# [Test] Files Plugin
echo "[Test] 60-files.sh (Symlinking)"
mkdir -p "$HOME/dotfiles"
touch "$HOME/dotfiles/.vimrc"
echo '{"files": [{"source": "~/dotfiles/.vimrc", "target": "~/.vimrc"}]}' > "$USER_CONFIG_PATH"

source "$PLUGIN_DIR/60-files.sh"

assert_file_exists "$HOME/.vimrc"
assert_eq "$(readlink "$HOME/.vimrc")" "$HOME/dotfiles/.vimrc" "Symlink target is correct"

# [Test] Env Plugin
echo "[Test] 45-env.sh (Variable Injection)"
echo '{"env": {"TEST_VAR": "production_ready"}}' > "$USER_CONFIG_PATH"

source "$PLUGIN_DIR/45-env.sh"

assert_file_exists "$USER_ENV_FILE"
if grep -q 'export TEST_VAR="production_ready"' "$USER_ENV_FILE"; then
    echo -e "  \e[32m[PASS]\e[0m Env file contains correct export"
else
    echo -e "  \e[31m[FAIL]\e[0m Env file content incorrect"
    cat "$USER_ENV_FILE"
    exit 1
fi

# [Test] Scripts Plugin
echo "[Test] 50-scripts.sh (Execution)"
echo '{"scripts": ["echo MOCK_SCRIPT_RUNNING >> '$AUDIT_LOG'"]}' > "$USER_CONFIG_PATH"

source "$PLUGIN_DIR/50-scripts.sh"

assert_audit "MOCK_SCRIPT_RUNNING"

echo "All plugin side-effects confirmed."