
# Dev Container Profile (devcontainer-profile)

Late-binds personal settings, dotfiles, and tools from a config file.

## Example Usage

```json
"features": {
    "ghcr.io/q4rk/devcontainer-features/devcontainer-profile:0": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| allowSudo | Allow the feature to configure passwordless sudo for the non-root user. Makes package installation easier | boolean | true |
| restoreOnCreate | Automatically apply the profile when the container is created. Defaults to true. | boolean | true |

## What does the feature do?
The **.devcontainer.profile** feature is a decoupled customization engine for Dev Containers. It allows developers to "late-bind" their personal preferences—tools, languages, dotfiles, VS Code extensions, and machine settings—to a container at runtime without modifying the project's shared `devcontainer.json` or `Dockerfile`.
*   **Decoupled & Personal:** Keeps your personal toolbelt in an isolated config. The project repository stays clean.
*   **Declarative Simplicity:** High-level keys (`apt`, `pip`, etc.) are kept simple for 90% of use cases. For complex flags or custom logic, use the powerful `scripts` block.
*   **Solid Persistence:** Uses a dedicated Docker volume and a **Solid Directory Link** (`~/.devcontainer.profile/`). Any file operations (creation, replacement, deletion) performed inside this directory in the container are immediately reflected in the persistent volume and survive rebuilds.
*   **Fail-Soft & Self-Healing:** The engine is designed to never crash the container build. It atomizes plugin execution and automatically restores the persistent link on every run if it is missing or broken.

## Quick Start

### 2. Start & Configure
Rebuild your Dev Container. Once inside, create your configuration file:

```bash
# The directory is automatically created and linked to a persistent volume
nano ~/.devcontainer.profile/config.json
```

Paste your configuration (see example below).

### 3. Apply
Apply your changes immediately:

```bash
apply-profile
```

**That's it!** Your configuration is now active and will persist across container rebuilds automatically.

### Host Seeding (Optional)
If you want to share your profile across multiple containers or seed it from your host machine, you can mount a local directory:

```json
"mounts": [
  {
    "source": "${localEnv:HOME}/.config/devcontainer-profile",
    "target": "/home/vscode/.config/devcontainer-profile",
    "type": "bind"
  }
]
```
*   **Note:** The engine will automatically discover config files mounted at `~/.config/devcontainer-profile/`.

## Example `config.json`

```json
{
  "apt": ["htop", "tree", "cowsay"],
  "vscode-extensions": [
    "ms-azuretools.vscode-docker",
    "eamodio.gitlens"
  ],
  "vscode-settings": {
    "editor.fontSize": 14,
    "terminal.integrated.fontSize": 14,
    "workbench.colorTheme": "Default Dark Modern"
  },
  "env": {
    "EDITOR": "vim",
    "GITHUB_TOKEN": "your_personal_token_here"
  },
  "pip": ["thefuck", "glances"],
  "npm": ["emoj"],
  "go": ["github.com/jesseduffield/lazygit@latest"],
  "features": [
    {
      "id": "ghcr.io/devcontainers/features/github-cli:1",
      "options": { "version": "latest" }
    }
  ],
  "scripts": [
    "echo 'alias gs=\"git status\"' >> ~/.bashrc"
  ]
}
```

## Manual Trigger

If you modify your configuration inside the container and want to apply changes immediately without rebuilding, run:

```bash
apply-profile
```

(or `devcontainer-profile-apply`)


## Core Concepts

### The Managed Directory
The engine establishes a symlink from `~/.devcontainer.profile` (container) to a persistent volume. This directory acts as your personal workspace:
*   `~/.devcontainer.profile/config.json`: Your primary configuration.
*   Any other files you place here (e.g., SSH keys, secret tokens) will persist across container rebuilds.

### VS Code Integration
*   **Extensions:** Automatically installs missing extensions using the `code` CLI.
*   **Machine Settings:** Merges your preferences into the VS Code Server's `Machine/settings.json`. This overrides project defaults without modifying the shared `.vscode/settings.json`.

### Shell History
*   **Persistent History:** Automatically configures Bash, Zsh, and Fish to store command history in the persistent volume (`.../shellhistory/`). 
*   **Default Behavior:** Enabled by default. Disable by setting `"shell-history": false`.
*   **Customizable Size:** Defaults to 10,000 lines. Customize with `"shell-history-size": 20000`.

## Language Support

The system provides native "polyglot" support for popular language package managers.

| Key | Description | Installation Path |
| :--- | :--- | :--- |
| **pip** | Python packages. | `~/.local/bin` |
| **npm** | Node.js global packages. | Global (via `npm install -g`) |
| **go** | Go binaries. | `~/go/bin` |
| **cargo** | Rust binaries. | `~/.cargo/bin` |

### Advanced Configuration
Instead of a simple list, you can provide an object to specify the binary to use:

```json
{
  "pip": {
    "bin": "pip3.11",
    "packages": ["black", "mypy"]
  },
  "npm": {
    "bin": "pnpm",
    "packages": ["typescript"]
  }
}
```

### Versioning Syntax
Each manager supports its native versioning syntax within the JSON configuration:

| Manager | Syntax | Example |
| :--- | :--- | :--- |
| **pip** | `==`, `>=`, `~=` | `"black==23.3.0"` |
| **npm** | `@` | `"prettier@3.0.0"` |
| **go** | `@` | `"golang.org/x/tools/gopls@v0.14.0"` |
| **cargo** | `@` | `"ripgrep@13.0.0"` |

**APT Versioning:**
```json
"apt": [
  { "name": "tree", "version": "2.1.0-1" },
  { "name": "jq", "version": "*" }
]
```

## Dotfiles & File Management

You can define a list of source-to-target mappings for symlinking.

```json
{
  "files": [
    { "source": "~/dotfiles/.vimrc", "target": "~/.vimrc" },
    { "source": "~/dotfiles/.zshrc", "target": "~/.zshrc" },
    { "source": "$HOME/secrets/npmrc", "target": "~/.npmrc" }
  ]
}
```

### Execution Order
Scripts run before Files. This allows you to clone a dotfiles repo before symlinking from it.

```json
{
  "scripts": [
    "if [ ! -d $HOME/dotfiles ]; then git clone https://github.com/user/dotfiles.git $HOME/dotfiles; fi",
    "git -C $HOME/dotfiles pull"
  ],
  "files": [
    { "source": "$HOME/dotfiles/.gitconfig", "target": "~/.gitconfig" }
  ]
}
```

## Troubleshooting

If your personalizations aren't appearing, follow these steps:

### 1. Check the Logs
The engine logs extensively to both a file and the terminal (stderr).
*   **View log file:** `cat /var/tmp/devcontainer-profile/state/profile.log`
*   **VS Code Terminal:** Check the "Dev Containers" output window.
*   **Terminal Launch:** If your configuration is invalid (e.g., bad JSON), you will see a warning message every time you open a new Bash or Zsh terminal. Check the logs mentioned above to fix the syntax error.

### 2. Force a Re-run
Customizations are only applied if the config file hash changes or the container is new. To force a re-run manually:
1.  **Delete the hash file:** `rm /var/tmp/devcontainer-profile/state/last_applied_hash`
2.  **Run the engine:** `apply-profile`

### 3. Check for Stale Locks
*   **Check lock status:** `ls -l /var/tmp/devcontainer-profile/state/engine.lock`
*   **Force unlock:** `apply-profile --force`

### 4. PATH Issues
If a tool is installed but you get `command not found`:
1.  Verify the path exists in `~/.devcontainer.profile_path`.
2.  Ensure `~/.bashrc` has the path-sourcing snippet at the **top**.
3.  Try running `source ~/.bashrc` in your current terminal.

### 5. Locks
If the command hangs with "Waiting for lock...", another process is running. If you are sure the previous process is stuck, force execution:
```bash
apply-profile --force
```

---
*Note: This feature is designed for Debian-based distributions.*


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/q4rk/devcontainer-features/blob/main/src/devcontainer-profile/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
