#!/bin/bash
set -e

echo ">>> [Test-All] Running unit and integration tests..."

# 1. Run Unit Tests (Fast, Mocked)
# We run these locally without spinning up a container to get fast feedback loop.
# Note: This assumes we are inside the dev container or a linux host with bash/jq.
if [ -f "./test/devcontainer-profile/test_runner_local.sh" ]; then
    echo ">>> Running Local Unit Tests..."
    ./test/devcontainer-profile/test_runner_local.sh
fi

echo ">>> Running Feature Scenarios (Dockerized)..."
devcontainer features test -f devcontainer-profile --project-folder .