#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

# Helper to run tests as the correct user
run_test() {
    local label="$1"
    local cmd="$2"
    if id "vscode" >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]]; then
        check "$label" sudo -u vscode bash -c "source dev-container-features-test-lib && $cmd"
    else
        check "$label" bash -c "$cmd"
    fi
}

# Integration checks: Verify installation
check "apply.sh is installed" ls /usr/local/share/devcontainer-profile/scripts/apply.sh
check "plugins are installed" ls /usr/local/share/devcontainer-profile/plugins/10-apt.sh

# Logic checks: Run unit tests
run_test "unit-test-engine" "./test_engine.sh"
run_test "unit-test-parsing" "./test_parsing.sh"
run_test "unit-test-plugins" "./test_plugins.sh"
run_test "unit-test-xdg" "./test_xdg.sh"

reportResults
