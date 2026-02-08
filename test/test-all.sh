#!/usr/bin/env bash
set -e

echo "=== [Phase 1] Standard Tests (Install & Unit) ==="
# Runs the 'test.sh' inside the container, which triggers our unit test suite
devcontainer features test -f devcontainer-profile --project-folder .

echo -e "\n=== [Phase 2] Scenario Integration Tests ==="
# Runs the specific scenario scripts defined in scenarios.json
devcontainer features test --scenarios test/devcontainer-profile --project-folder .