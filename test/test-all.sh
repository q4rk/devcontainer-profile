#!/bin/bash
set -e

echo ">>> [Test-All] Running unit and integration tests..."

# 1. Run Unit Tests (Fast, Mocked)
echo ">>> Running Local Unit Tests..."
chmod +x test/devcontainer-profile/*.sh

./test/devcontainer-profile/test_unit_engine.sh
./test/devcontainer-profile/test_unit_plugins.sh
./test/devcontainer-profile/test_unit_xdg.sh

echo ">>> Running Feature Scenarios (Dockerized)..."
devcontainer features test -f devcontainer-profile --project-folder .