#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

readonly FEATURE_NAME="devcontainer-profile"
readonly INSTALL_DIR="/usr/local/share/${FEATURE_NAME}"
readonly BIN_DIR="/usr/local/bin"

ALLOWSUDO="${ALLOWSUDO:-true}"
RESTOREONCREATE="${RESTOREONCREATE:-true}"

echo ">>> [${FEATURE_NAME}] Starting build-time installation..."

persist_feature_config() {
    echo ">>> [${FEATURE_NAME}] Persisting feature configuration..."
    mkdir -p "${INSTALL_DIR}"
    echo "RESTOREONCREATE=\"${RESTOREONCREATE}\"" > "${INSTALL_DIR}/feature_config.sh"
    chmod 644 "${INSTALL_DIR}/feature_config.sh"
}

cleanup_broken_repos() {
    if [ -f "/etc/apt/sources.list.d/yarn.list" ]; then
        echo ">>> [${FEATURE_NAME}] Removing potentially broken yarn.list..."
        rm -f "/etc/apt/sources.list.d/yarn.list"
    fi
}

ensure_dependencies() {
    cleanup_broken_repos
    if ! command -v jq >/dev/null 2>&1 || \
       ! command -v curl >/dev/null 2>&1 || \
       ! command -v unzip >/dev/null 2>&1 || \
       ! command -v gpg >/dev/null 2>&1;
    then
        
        echo ">>> [${FEATURE_NAME}] Installing base dependencies..."
        export DEBIAN_FRONTEND=noninteractive
        
        # Try twice
        apt-get update -y || (sleep 2 && apt-get update -y) || echo "(!) [${FEATURE_NAME}] Warning: apt-get update had errors."

        apt-get install -y --no-install-recommends \
            jq curl ca-certificates unzip gnupg || \
            echo "(!) [${FEATURE_NAME}] Warning: Dependency installation failed. Runtime features may be limited."
    fi
}

install_feature_installer() {
    echo ">>> [${FEATURE_NAME}] Installing feature-installer..."
    local installer_url="https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh"
    
    if ! curl -fsSL "${installer_url}" | bash; then
        echo "(!) ERROR: Failed to install feature-installer. Feature installation will be disabled."
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

configure_sudo_and_user() {
    if [ "${ALLOWSUDO}" != "true" ] || [ "${_REMOTE_USER}" = "root" ]; then
        echo ">>> [${FEATURE_NAME}] Sudo configuration disabled or running as root."
        return 0
    fi
    local user="${_REMOTE_USER}"
    echo ">>> [${FEATURE_NAME}] Configuring Sudo for user: ${user}..."
    if ! command -v sudo >/dev/null 2>&1; then
        apt-get update && apt-get install -y sudo && apt-get clean && rm -rf /var/lib/apt/lists/*
    fi
    if ! id "${user}" >/dev/null 2>&1; then
        echo ">>> [${FEATURE_NAME}] Creating user ${user}..."
        groupadd --gid 1000 "${user}" || true
        useradd --uid 1000 --gid 1000 -m -s /bin/bash "${user}"
    fi
    if ! getent group sudo >/dev/null 2>&1; then groupadd sudo; fi
    usermod -aG sudo "${user}"
    local sudoers_file="/etc/sudoers.d/${user}-nopasswd"
    echo "${user} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    echo ">>> [${FEATURE_NAME}] User configured successfully."
}

deploy_assets() {
    echo ">>> [${FEATURE_NAME}] Deploying scripts and plugins..."
    
    mkdir -p "${INSTALL_DIR}/scripts"
    mkdir -p "${INSTALL_DIR}/plugins"
    mkdir -p "${INSTALL_DIR}/lib"
    
    # Create the workspace directories with sticky bit so users can create 'shellhistory' etc.
    mkdir -p /var/tmp/devcontainer-profile
    chmod 1777 /var/tmp/devcontainer-profile

    mkdir -p /var/tmp/devcontainer-profile/state
    chmod 1777 /var/tmp/devcontainer-profile/state

    if [ -d "./scripts" ]; then
        cp ./scripts/apply.sh "${INSTALL_DIR}/scripts/"
        cp -r ./scripts/lib "${INSTALL_DIR}/"
        cp ./scripts/plugins/*.sh "${INSTALL_DIR}/plugins/"
        
        chmod +x "${INSTALL_DIR}/scripts/apply.sh"
        chmod +x "${INSTALL_DIR}/plugins/"*.sh
    else
        echo "(!) [${FEATURE_NAME}] FATAL: Source scripts directory not found."
        exit 1
    fi
}

apply_alias() {
    echo ">>> [${FEATURE_NAME}] Creating 'apply-profile' symlink..."
    # Create a symlink in /usr/local/bin so it's in the PATH also create a namespaced alias for clarity
    ln -sf "${INSTALL_DIR}/scripts/apply.sh" "${BIN_DIR}/apply-profile"
    chmod +x "${BIN_DIR}/apply-profile"
    ln -sf "${INSTALL_DIR}/scripts/apply.sh" "${BIN_DIR}/devcontainer-profile-apply"
    chmod +x "${BIN_DIR}/devcontainer-profile-apply"
}

persist_feature_config
ensure_dependencies
install_feature_installer
configure_sudo_and_user
deploy_assets
apply_alias

echo ">>> [${FEATURE_NAME}] Build-time installation complete."
