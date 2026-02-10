#!/bin/bash
set -o errexit
set -o pipefail

# Bootstrap
source "$(dirname "$0")/test_utils.sh"
setup_hermetic_env

cleanup() {
    echo ">>> Final Profile Log: unit engine test"
    cat "$LOG_FILE" 2>/dev/null || echo "(Log file empty or missing)"
    teardown_hermetic_env
}
trap cleanup EXIT

echo "=== [Unit] Engine Core Logic Tests ==="

# Mock dependencies
mock_tool "sudo"
mock_tool "apt-get"
mock_tool "code"
# We will rely on real md5sum
# Override simple mocks with specific behavior if needed, or rely on system tools for logic
# For logic tests, we actually want REAL coreutils (md5sum, ln, cp) to test the script's logic.
# We only mock heavy lifters like apt/git.

# --- Test 1: Config Discovery & Ingestion ---
echo "--- Test 1: Config Ingestion ---"
mkdir -p "$WORKSPACE/.config/.devcontainer.profile"
echo '{"apt": ["vim"]}' > "$WORKSPACE/.config/.devcontainer.profile/config.json"

# Run Apply
"$INSTALL_DIR/scripts/apply.sh"

assert_file_exists "$VOLUME_CONFIG_DIR/config.json"
assert_file_exists "$MANAGED_CONFIG_DIR/config.json"
log_pass "Configuration ingested and symlinked"

echo "--- Test 2: Hashing & caching ---"
# First run already happened.
HASH_FILE="$STATE_DIR/last_applied_hash"
assert_file_exists "$HASH_FILE"
FIRST_HASH=$(cat "$HASH_FILE")

# Run again (Should be no-op)
# We can verify this by checking if the log says "skipping"
"$INSTALL_DIR/scripts/apply.sh"
if grep -q "No changes detected" "$LOG_FILE"; then
    log_pass "Idempotency verified (skipped execution)"
else
    log_fail "Engine re-ran despite no config change"
fi

# Modify config
echo '{"apt": ["vim", "nano"]}' > "$VOLUME_CONFIG_DIR/config.json"
"$INSTALL_DIR/scripts/apply.sh"
NEW_HASH=$(cat "$HASH_FILE")

if [[ "$FIRST_HASH" != "$NEW_HASH" ]]; then
    log_pass "Hash updated on config change"
else
    log_fail "Hash did not update"
fi

echo "--- Test 3: Concurrency Locking ---"
# We simulate a held lock by opening a file descriptor in a background process
(
    exec 200> "$STATE_DIR/engine.lock"
    flock -x 200
    sleep 3
) &
BG_PID=$!
sleep 0.5

# Try running engine - it should wait
START_TIME=$(date +%s)
"$INSTALL_DIR/scripts/apply.sh"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ $DURATION -ge 2 ]]; then
    log_pass "Engine waited for lock (${DURATION}s)"
else
    log_fail "Engine ignored lock (completed in ${DURATION}s)"
fi

echo "--- Test 4: Force Lock Breaking ---"
# Start a background process that holds the lock indefinitely
(
    exec 200<> "$STATE_DIR/engine.lock"
    flock -x 200
    # Write PID to lock file as the real script does
    echo "$BASHPID" > "$STATE_DIR/engine.lock"
    sleep 30
) &
STUCK_PID=$!
sleep 0.5

# Verify lock is held
if ! kill -0 "$STUCK_PID" 2>/dev/null; then
    log_fail "Setup failed: Stuck process died prematurely"
fi

echo "Attempting to break lock held by PID $STUCK_PID..."
START_TIME=$(date +%s)
"$INSTALL_DIR/scripts/apply.sh" --force
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Check if the stuck process was killed
if kill -0 "$STUCK_PID" 2>/dev/null; then
    log_fail "Force mode failed to kill the stuck process"
    kill "$STUCK_PID" 2>/dev/null || true
else
    log_pass "Stuck process was successfully killed"
fi

# Check if execution was fast (shouldn't wait 30s)
if [[ $DURATION -lt 5 ]]; then
    log_pass "Force mode proceeded immediately (${DURATION}s)"
else
    log_fail "Force mode waited too long (${DURATION}s)"
fi

echo "--- Test 5: Restore on Create Logic ---"

# Case A: Disabled (Default)
echo "RESTOREONCREATE=\"false\"" > "$INSTALL_DIR/feature_config.sh"
# We expect it to exit 0 but NOT run the logic (no lock file created)
rm -f "$STATE_DIR/engine.lock"
"$INSTALL_DIR/scripts/apply.sh" --restore-if-enabled

if [[ -f "$STATE_DIR/engine.lock" ]]; then
    log_fail "Engine ran despite restoreOnCreate=false"
else
    log_pass "Engine skipped execution when disabled"
fi

# Case B: Enabled
echo "RESTOREONCREATE=\"true\"" > "$INSTALL_DIR/feature_config.sh"
# We expect it to run (create lock file)
"$INSTALL_DIR/scripts/apply.sh" --restore-if-enabled

if [[ -f "$STATE_DIR/engine.lock" ]]; then
    log_pass "Engine ran when restoreOnCreate=true"
else
    log_fail "Engine failed to run when enabled"
fi

echo "--- Test 6: Invalid JSON Handling ---"
# Create invalid JSON
echo '{ "apt": ["vim", ' > "$VOLUME_CONFIG_DIR/config.json"
touch "$HOME/.bashrc"

# Run Apply
"$INSTALL_DIR/scripts/apply.sh"

# Check 1: Warning injected
if grep -q "Dev Container Profile Warning" "$HOME/.bashrc"; then
    log_pass "Warning injected into .bashrc"
else
    log_fail "Warning NOT found in .bashrc"
fi

# Check 2: Plugins still ran (check log for a plugin execution)
# We assume plugins run if the script didn't exit early.
# We can check if PROFILE_CONFIG_VALID=false was logged or handled?
# Better: Check if a default action happened.
# Since we don't have full plugins here, we rely on the fact that apply.sh completed successfully (exit code 0)
# and that the log contains the error message.
if grep -q "Invalid JSON in configuration file" "$LOG_FILE"; then
    log_pass "Error logged correctly"
else
    log_fail "Error not logged"
fi

# Check 3: Recovery
echo '{ "apt": ["vim"] }' > "$VOLUME_CONFIG_DIR/config.json"
"$INSTALL_DIR/scripts/apply.sh"

# Warning should be gone (replaced by empty string)
# The markers will be there, but the content between them should be empty/whitespace
if grep -q "Dev Container Profile Warning" "$HOME/.bashrc"; then
    log_fail "Warning persisted after fix"
else
    log_pass "Warning removed after fix"
fi

# --- Test 7: Missing Config Clears Warning ---
echo "--- Test 7: Missing Config Clears Warning ---"
# Setup: Create bad config again
echo '{ "apt": ["vim", ' > "$VOLUME_CONFIG_DIR/config.json"
"$INSTALL_DIR/scripts/apply.sh"
if ! grep -q "Dev Container Profile Warning" "$HOME/.bashrc"; then
    log_fail "Setup failed: Warning not injected"
fi

# Action: Delete config
rm "$VOLUME_CONFIG_DIR/config.json"
# We also need to remove the source config so it doesn't get re-ingested
rm -f "$WORKSPACE/.config/.devcontainer.profile/config.json"

# Run Apply
"$INSTALL_DIR/scripts/apply.sh"

# Verify: Warning gone
if grep -q "Dev Container Profile Warning" "$HOME/.bashrc"; then
    log_fail "Warning persisted after config deletion"
else
    log_pass "Warning removed after config deletion"
fi

# --- Test 8: New Valid Config Clears Stale Warning ---
echo "--- Test 8: New Valid Config Clears Stale Warning ---"
# Setup: Inject a fake stale warning
echo "# START: PROFILE_WARNING (devcontainer-profile)" >> "$HOME/.bashrc"
echo "echo '(!) Stale Warning'" >> "$HOME/.bashrc"
echo "# END: PROFILE_WARNING" >> "$HOME/.bashrc"

# Action: Add a VALID config
echo '{ "apt": ["curl"] }' > "$VOLUME_CONFIG_DIR/config.json"

"$INSTALL_DIR/scripts/apply.sh"

# Verify: Warning gone
if grep -q "Stale Warning" "$HOME/.bashrc"; then
    log_fail "Stale warning persisted after valid config applied"
else
    log_pass "Stale warning removed by valid config"
fi

echo "=== Engine Tests Passed ==="
