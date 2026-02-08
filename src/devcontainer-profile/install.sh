#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly FEATURE_NAME="devcontainer-profile"
readonly INSTALL_DIR="/usr/local/share/${FEATURE_NAME}"
readonly BIN_DIR="/usr/local/bin"

# Defaults to true, can be overridden by devcontainer-feature.json
ALLOWSUDO="${ALLOWSUDO:-true}"

echo ">>> [${FEATURE_NAME}] Starting build-time installation..."

ensure_dependencies() {
    # In the Dev Container Feature specification, the build process always executes your install.sh as the root user, 
    # regardless of what remoteUser is set to in devcontainer.json. This means the apt commands will work without sudo
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

# Install feature-installer (external tool for OCI features)
install_feature_installer() {
    echo ">>> [${FEATURE_NAME}] Installing feature-installer..."
    local installer_url="https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh"
    
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

# This handles User Creation in one standard call.
configure_sudo_and_user() {
    if [ "${ALLOWSUDO}" != "true" ] || [ "${_REMOTE_USER}" = "root" ]; then
        echo ">>> [${FEATURE_NAME}] Sudo configuration disabled or running as root."
        return 0
    fi

    local user="${_REMOTE_USER}"
    echo ">>> [${FEATURE_NAME}] Configuring Sudo for user: ${user}..."

    if command -v feature-installer >/dev/null 2>&1; then
        echo " Using feature-installer"
        # we invoke common-utils purely for the sudo/user logic
        if feature-installer feature install ghcr.io/devcontainers/features/common-utils:2 \
            --option installZsh=false \
            --option upgradePackages=false \
            --option username="${user}" \
            --option userUid=1000 \
            --option userGid=1000; then
            
            echo "User-configured successfully."
            return 0
        fi
        echo "(!) Warning: Feature installer failed. Falling back to manual method."
    fi

    echo "Manual Configuration (Fallback)..."
    if ! command -v sudo >/dev/null 2>&1; then
        apt-get update && apt-get install -y sudo && apt-get clean && rm -rf /var/lib/apt/lists/*
    fi
    if ! id "${user}" >/dev/null 2>&1; then
        echo "Creating user ${user}..."
        groupadd --gid 1000 "${user}" || true
        useradd --uid 1000 --gid 1000 -m -s /bin/bash "${user}"
    fi
    if ! getent group sudo >/dev/null 2>&1; then groupadd sudo; fi
    usermod -aG sudo "${user}"
    local sudoers_file="/etc/sudoers.d/${user}-nopasswd"
    echo "${user} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    echo "User-configured successfully."
}

configure_sudo_and_user

deploy_assets() {
    echo ">>> [${FEATURE_NAME}] Deploying scripts and plugins..."
    
    mkdir -p "${INSTALL_DIR}/scripts"
    mkdir -p "${INSTALL_DIR}/plugins"
    mkdir -p "${INSTALL_DIR}/lib"
    
    # Create the PARENT workspace with Sticky Bit so users can create 'shellhistory' etc.
    mkdir -p /var/tmp/devcontainer-profile
    chmod 1777 /var/tmp/devcontainer-profile

    # State directory (writable by users)
    mkdir -p /var/tmp/devcontainer-profile/state
    chmod 1777 /var/tmp/devcontainer-profile/state

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