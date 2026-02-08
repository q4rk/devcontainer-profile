#!/bin/bash
set -e
source dev-container-features-test-lib

check "script: apply.sh installed" test -x /usr/local/share/devcontainer-profile/scripts/apply.sh
check "dir: plugins exist" test -d /usr/local/share/devcontainer-profile/plugins

reportResults