#!/usr/bin/env bash
#
# install.sh
# entrypoint for the devcontainer feature build process
#

set -o errexit
set -o pipefail
set -o nounset

readonly NAME="devcontainer-profile"
readonly INSTALL_DIR="/usr/local/share/devcontainer-profile"
readonly BIN_DIR="/usr/local/bin"

log() { echo ">>> [${NAME}] $1"; }
error() { echo "!!! [${NAME}] ERROR: $1" >&2; }

# --- 1. Dependency Management ---
check_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_dependencies() {
    local missing=()
    # ca-certificates is critical for curl to verify SSL connections
    for cmd in jq curl sudo unzip gpg; do
        if ! check_cmd "$cmd"; then missing+=("$cmd"); fi
    done
    
    # Always ensure ca-certificates is present
    if ! dpkg -s ca-certificates >/dev/null 2>&1; then
        missing+=("ca-certificates")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log "Installing build dependencies: ${missing[*]}"
        export DEBIAN_FRONTEND=noninteractive
        
        # Resilient update: try update, but don't fail build if a 3rd party repo (irrelevant to us) is down
        if ! apt-get update -y; then
            echo "(!) Warning: apt-get update encountered errors, proceeding with cached lists..."
        fi

        if ! apt-get install -y --no-install-recommends "${missing[@]}"; then
            error "Failed to install dependencies."
            exit 1
        fi
        
        if check_cmd update-ca-certificates; then
            update-ca-certificates >/dev/null 2>&1 || true
        fi
    fi
}

# --- 2. Install Feature Installer ---
install_feature_installer() {
    log "Installing feature-installer..."
    local installer_url="https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh"
    
    if ! curl -fsSL "$installer_url" | bash; then
        error "Failed to download/install feature-installer."
        exit 1
    fi

    # Locate binary (root vs remote user paths can vary during build)
    local possible_paths=(
        "/root/.feature-installer/bin/feature-installer"
        "/home/${_REMOTE_USER:-vscode}/.feature-installer/bin/feature-installer"
    )

    local found_bin=""
    for p in "${possible_paths[@]}"; do
        if [ -f "$p" ]; then found_bin="$p"; break; fi
    done

    if [ -n "$found_bin" ]; then
        mv "$found_bin" "${BIN_DIR}/feature-installer"
        chmod +x "${BIN_DIR}/feature-installer"
    fi
}

# --- 3. Deploy Assets ---
deploy_assets() {
    log "Deploying scripts and plugins..."
    mkdir -p "${INSTALL_DIR}/scripts" "${INSTALL_DIR}/lib" "${INSTALL_DIR}/plugins"
    mkdir -p "/var/tmp/devcontainer-profile/state"

    # Copy Library
    if [ -f "./scripts/lib/utils.sh" ]; then
        cp ./scripts/lib/utils.sh "${INSTALL_DIR}/lib/utils.sh"
    else 
        # Create it if it doesn't exist in source (helper for the refactor context)
        mkdir -p "${INSTALL_DIR}/lib"
        touch "${INSTALL_DIR}/lib/utils.sh"
    fi

    # Copy Core Script
    cp ./scripts/apply.sh "${INSTALL_DIR}/scripts/apply.sh"
    chmod +x "${INSTALL_DIR}/scripts/apply.sh"

    # Copy Plugins
    if [ -d "./scripts/plugins" ]; then
        cp ./scripts/plugins/*.sh "${INSTALL_DIR}/plugins/"
        chmod +x "${INSTALL_DIR}/plugins/"*.sh
    fi
}

# --- 4. Permissions ---
set_permissions() {
    local target_user="${_REMOTE_USER:-vscode}"
    if [ "$target_user" != "root" ]; then
        # Ensure the temp directory is writable by the user
        chown -R "$target_user:$target_user" /var/tmp/devcontainer-profile || true
    fi
}

main() {
    ensure_dependencies
    install_feature_installer
    deploy_assets
    set_permissions
    log "Installation complete."
}

main "$@"