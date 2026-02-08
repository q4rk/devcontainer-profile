#!/bin/bash
source /tmp/test_lib.sh

setup_suite
mock_utils

# We need to simulate the mount points
CONFIG_MOUNT="$TEST_ROOT/mount"
FALLBACK_MOUNT="$TEST_ROOT/fallback"
mkdir -p "$CONFIG_MOUNT" "$FALLBACK_MOUNT"

# Extract the discovery logic from apply.sh for isolation testing
# (Or we could source apply.sh, but that runs everything. We just want to test the loop logic)
discover_config() {
    local config_source=""
    local discovery_dirs=("${CONFIG_MOUNT}" "${FALLBACK_MOUNT}")
    for d in "${discovery_dirs[@]}"; do
        if [[ -f "${d}" ]]; then config_source="${d}"; break
        elif [[ -d "${d}" ]]; then
            for f in "config.json" "devcontainer.profile.json" ".devcontainer.profile"; do
                 if [[ -f "${d}/${f}" ]]; then config_source="${d}/${f}"; break 2; fi
            done
        fi
    done
    echo "$config_source"
}

echo "=== XDG Discovery Tests ==="

# 1. Direct File Mount
touch "$CONFIG_MOUNT" # Simulate it being a file
# Note: In bash, -f returns true for file, -d false.
assert_eq "$CONFIG_MOUNT" "$(discover_config)" "Detects direct file mount"
rm "$CONFIG_MOUNT" && mkdir "$CONFIG_MOUNT"

# 2. Priority: config.json
touch "$CONFIG_MOUNT/config.json"
touch "$CONFIG_MOUNT/.devcontainer.profile"
assert_eq "$CONFIG_MOUNT/config.json" "$(discover_config)" "Prioritizes config.json"
rm "$CONFIG_MOUNT/config.json"

# 3. Priority: .devcontainer.profile
assert_eq "$CONFIG_MOUNT/.devcontainer.profile" "$(discover_config)" "Fallback to .devcontainer.profile"
rm "$CONFIG_MOUNT/.devcontainer.profile"

# 4. Fallback Mount
touch "$FALLBACK_MOUNT/config.json"
assert_eq "$FALLBACK_MOUNT/config.json" "$(discover_config)" "Fallback directory check"

echo "XDG Discovery logic confirmed."