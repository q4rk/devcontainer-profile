#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly name="devcontainer-profile"
echo ">>> [$name] Installing build-time components..."

# Helper to check if a command exists
check_cmd() { command -v "$1" >/dev/null 2>&1; }

# Install dependencies if missing
if ! check_cmd jq || ! check_cmd curl || ! check_cmd sudo || ! check_cmd unzip || ! check_cmd gpg; then
    echo ">>> [$name] Installing missing dependencies (jq, curl, sudo, unzip, gpg)..."
    export DEBIAN_FRONTEND=noninteractive
    # We allow update to fail because some base images have broken third-party repos (like Yarn)
    # that we don't depend on. We use '|| true' to be absolutely sure it doesn't trigger errexit.
    apt-get update -y || true
    
    # Try to install, but don't fail the whole build if it fails (late-binding philosophy)
    apt-get install -y jq curl ca-certificates sudo unzip gnupg || echo "(!) Warning: Dependency installation failed."
fi

echo ">>> [$name] Installing feature-installer..."
# We use -f for curl to fail on server errors, but we wrap in a check
if ! curl -fsSL https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh | bash; then
    echo "(!) ERROR: Failed to install feature-installer. This is a fatal error."
    exit 1
fi

# locate and move binary (Handle root vs non-root paths)
INSTALLED_BIN=""
REMOTE_USER="${_REMOTE_USER:-vscode}"
if [ -f "/root/.feature-installer/bin/feature-installer" ]; then
    INSTALLED_BIN="/root/.feature-installer/bin/feature-installer"
elif [ -f "/home/${REMOTE_USER}/.feature-installer/bin/feature-installer" ]; then
    INSTALLED_BIN="/home/${REMOTE_USER}/.feature-installer/bin/feature-installer"
fi

if [ -n "$INSTALLED_BIN" ] && [ -f "$INSTALLED_BIN" ]; then
    mv "$INSTALLED_BIN" "/usr/local/bin/feature-installer"
    chmod +x "/usr/local/bin/feature-installer"
fi

echo ">>> [$name] Deploying engine & plugins..."

mkdir -p /usr/local/share/devcontainer-profile/scripts
mkdir -p /usr/local/share/devcontainer-profile/plugins
mkdir -p /var/tmp/devcontainer-profile/state

if [ -f "./scripts/apply.sh" ]; then
    cp ./scripts/apply.sh /usr/local/share/devcontainer-profile/scripts/apply.sh
    chmod +x /usr/local/share/devcontainer-profile/scripts/apply.sh
else
    echo "(!) ERROR: scripts/apply.sh missing."
    exit 1
fi

if [ -d "./scripts/plugins" ]; then
    cp ./scripts/plugins/*.sh /usr/local/share/devcontainer-profile/plugins/
    chmod +x /usr/local/share/devcontainer-profile/plugins/*.sh
else
    echo "(!) ERROR: scripts/plugins directory missing."
    exit 1
fi

if [ -n "${_REMOTE_USER}" ] && [ "${_REMOTE_USER}" != "root" ]; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" /var/tmp/devcontainer-profile || true
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" /usr/local/share/devcontainer-profile || true
fi

echo ">>> [$name] Installation complete."
