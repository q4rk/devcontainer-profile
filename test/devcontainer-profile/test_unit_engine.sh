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

# --- Test 2: Hashing & Idempotency ---
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

# --- Test 3: Locking Mechanism ---
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

echo "=== Engine Tests Passed ==="
