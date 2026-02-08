#!/bin/bash
# 01-diagnostics.sh - System health check
source "${LIB_PATH}"

info "Diagnostics" "User: ${TARGET_USER} (UID: $(id -u))"
info "Diagnostics" "Home: ${TARGET_HOME}"
info "Diagnostics" "Config: ${USER_CONFIG_PATH}"

check_tool() {
    if command -v "$1" >/dev/null 2>&1; then
        info "Diagnostics" "Found: $1 ($(command -v "$1"))"
    else
        info "Diagnostics" "Missing: $1"
    fi
}

check_tool jq
check_tool curl
check_tool git
check_tool code