#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly FEATURE_NAME="devcontainer-profile"
readonly INSTALL_DIR="/usr/local/share/${FEATURE_NAME}"
readonly BIN_DIR="/usr/local/bin"

echo ">>> [${FEATURE_NAME}] Starting build-time installation..."

# 1. Dependency Check & Install
# We use a single apt-get line to minimize layer updates and ensure consistency.
ensure_dependencies() {
    if ! command -v jq >/dev/null 2>&1 || \
       ! command -v curl >/dev/null 2>&1 || \
       ! command -v sudo >/dev/null 2>&1 || \
       ! command -v unzip >/dev/null 2>&1 || \
       ! command -v gpg >/dev/null 2>&1; then
        
        echo ">>> [${FEATURE_NAME}] Installing dependencies..."
        export DEBIAN_FRONTEND=noninteractive
        
        # Robust update: Try twice, do not fail build on repo errors (common in devcontainers)
        apt-get update -y || (sleep 2 && apt-get update -y) || echo "(!) Warning: apt-get update had errors."

        # Fail soft on install to allow build to proceed (late-binding philosophy)
        apt-get install -y --no-install-recommends \
            jq curl ca-certificates sudo unzip gnupg || \
            echo "(!) Warning: Dependency installation failed. Runtime features may be limited."
    fi
}

ensure_dependencies

# 2. Install feature-installer (external tool for OCI features)
install_feature_installer() {
    echo ">>> [${FEATURE_NAME}] Installing feature-installer..."
    local installer_url="https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh"
    
    # Secure download execution
    if ! curl -fsSL "$installer_url" | bash; then
        echo "(!) ERROR: Failed to install feature-installer. Feature installation will be disabled."
        # We do not exit 1 here to strictly adhere to "Fail Soft" for the overall build
    else
        # Move binary to global path if not already there
        # The installer usually places it in user home or root home
        local possible_paths=(
            "/root/.feature-installer/bin/feature-installer"
            "/home/${_REMOTE_USER:-vscode}/.feature-installer/bin/feature-installer"
        )
        
        for p in "${possible_paths[@]}"; do
            if [ -f "$p" ]; then
                mv "$p" "${BIN_DIR}/feature-installer"
                chmod +x "${BIN_DIR}/feature-installer"
                echo ">>> [${FEATURE_NAME}] feature-installer moved to ${BIN_DIR}"
                break
            fi
        done
    fi
}

install_feature_installer

# 3. Deploy Engine & Plugins
deploy_assets() {
    echo ">>> [${FEATURE_NAME}] Deploying scripts and plugins..."
    
    mkdir -p "${INSTALL_DIR}/scripts"
    mkdir -p "${INSTALL_DIR}/plugins"
    mkdir -p "${INSTALL_DIR}/lib"
    
    # State directory (writable by users)
    mkdir -p /var/tmp/devcontainer-profile/state
    chmod 1777 /var/tmp/devcontainer-profile/state

    # Copy Core Logic
    if [ -d "./scripts" ]; then
        cp ./scripts/apply.sh "${INSTALL_DIR}/scripts/"
        cp -r ./scripts/lib "${INSTALL_DIR}/"
        cp ./scripts/plugins/*.sh "${INSTALL_DIR}/plugins/"
        
        chmod +x "${INSTALL_DIR}/scripts/apply.sh"
        chmod +x "${INSTALL_DIR}/plugins/"*.sh
    else
        echo "(!) FATAL: Source scripts directory not found."
        exit 1
    fi
}

deploy_assets

echo ">>> [${FEATURE_NAME}] Build-time installation complete."