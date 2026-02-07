#!/bin/bash
set -e

echo "Running standard tests..."
devcontainer features test -f devcontainer-profile --base-path .

echo "Running scenario tests..."
devcontainer features test --scenarios test/devcontainer-profile --base-path .
