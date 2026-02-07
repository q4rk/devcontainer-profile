#!/bin/bash
set -e

# Import test library
source dev-container-features-test-lib

check "apply.sh exists" ls /usr/local/share/devcontainer-profile/scripts/apply.sh
check "plugins directory exists" ls /usr/local/share/devcontainer-profile/plugins/10-apt.sh

reportResults
