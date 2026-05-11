#!/bin/bash
set -e

# Setup Script Bootstrap
# Download and run with:
# ```bash
# wget https://raw.githubusercontent.com/artofthesmart/shell-setup/main/bootstrap.sh -O bootstrap.sh
# chmod +x bootstrap.sh
# ./bootstrap.sh
# ```

# Prevent piping to bash
if [ ! -t 0 ]; then
    echo "ERROR: This script must be downloaded and run directly, not piped to bash."
    echo "Please run: wget <URL> -O bootstrap.sh && chmod +x bootstrap.sh && ./bootstrap.sh"
    exit 1
fi

echo "--- Bootstrapping shell-setup ---"

# Require sudo privileges upfront
if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: You are not root and sudo is not installed. Please run as root."
        exit 1
    fi
    # Prompt for password now to cache credentials
    sudo -v
fi

# Install dependencies needed for python/uv
echo "Installing base dependencies..."
sudo apt-get update -y
sudo apt-get install -y curl python3 python3-pip python3-venv git zsh

# Install uv if not present
if ! command -v uv >/dev/null 2>&1; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# Make sure zsh is the default shell
USER_NAME="$(whoami)"
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
    echo "Setting zsh as default shell..."
    sudo chsh -s "$ZSH_PATH" "$USER_NAME"
fi

# Ensure setup.py exists
if [ ! -f "setup.py" ]; then
    # In a real environment, we'd wget setup.py here. Since they are in the same repo, it should be present.
    if [ -f "$(dirname "$0")/setup.py" ]; then
        cd "$(dirname "$0")"
    else
        echo "ERROR: setup.py not found in current directory."
        exit 1
    fi
fi

# Re-execute in zsh and run the Python script
echo "Launching modern hybrid setup..."
exec zsh -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; uv run --with rich --with questionary setup.py"
