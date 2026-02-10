#!/bin/bash
set -e

# Import standard features test lib
source dev-container-features-test-lib

# We run the unit tests *inside* the scenario container to ensure the environment
# capabilities (bash version, tools) match the target.
run_unit_test() {
    local test_script="$1"
    local description="$2"
    
    echo "    > Running: $description ($test_script)"
    if bash "./$test_script"; then
        check "$description" true
    else
        check "$description" false
        echo "(!) FAILED: $test_script"
        echo ">>> Dumping Profile Log for Diagnostics:"
        cat /var/tmp/devcontainer-profile/state/profile.log 2>/dev/null || echo "(Log file empty or missing)"
        exit 1
    fi
}

echo ">>> Phase 1: Engine Unit Tests (Mocked Filesystem)"
run_unit_test "test_unit_engine.sh" "Core Engine Logic"
run_unit_test "test_unit_plugins.sh" "Plugin Execution & Parsing"
run_unit_test "test_unit_xdg.sh" "XDG Discovery Logic"

# Verify that the feature actually installed the layout correctly
echo ">>> Phase 2: Installation Layout Verification"
check "apply.sh installed" ls /usr/local/share/devcontainer-profile/scripts/apply.sh
check "lib installed" ls /usr/local/share/devcontainer-profile/lib/utils.sh
check "plugins installed" ls /usr/local/share/devcontainer-profile/plugins/10-apt.sh
check "apply-profile symlink installed" ls /usr/local/bin/apply-profile

reportResults