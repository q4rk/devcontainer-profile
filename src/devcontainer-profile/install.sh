#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly name="devcontainer-profile"
echo ">>> [$name] Installing build-time components..."

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then apt-get update -y; fi
}
apt_get_update
apt-get install -y jq curl ca-certificates sudo

echo ">>> [$name] Installing feature-installer..."
curl -fsSL https://raw.githubusercontent.com/devcontainer-community/feature-installer/main/scripts/install.sh | bash

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
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" /var/tmp/devcontainer-profile
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" /usr/local/share/devcontainer-profile
fi

echo ">>> [$name] Installation complete."
