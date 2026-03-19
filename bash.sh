#!/bin/bash
set -e

# Setup script for Ubuntu/Raspbian

# Output helpers
info() { echo -e "\e[32m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }

# Detect sudo
SUDO=''
if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO='sudo'
    else
        warn "You are not root and sudo is not installed. Please run as root."
        exit 1
    fi
fi

USER_HOME="$HOME"
USER_NAME="$(whoami)"

info "Updating and upgrading apt packages..."
$SUDO apt-get update -y
$SUDO apt-get upgrade -y

info "Installing base utilities and packages..."
# Installing neovim as well since it's required for LazyVim
# ripgrep and fd-find are also highly recommended for LazyVim
$SUDO apt-get install -y \
  zsh \
  vim \
  neovim \
  python3 \
  python3-pip \
  python3-venv \
  gpg \
  make \
  man-db \
  gcc \
  unzip \
  wget \
  curl \
  git \
  nodejs \
  npm \
  ripgrep \
  fd-find \
  fontconfig

info "Installing GitHub CLI..."
if ! command -v gh &> /dev/null; then
  $SUDO mkdir -p -m 755 /etc/apt/keyrings
  GH_KEYRING_TMP=$(mktemp)
  wget -nv -O "$GH_KEYRING_TMP" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$GH_KEYRING_TMP" | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install gh -y
  rm -f "$GH_KEYRING_TMP"
else
  info "GitHub CLI already installed."
fi

info "Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  info "Tailscale already installed."
fi

info "Installing Gemini CLI..."
if ! command -v gemini &> /dev/null; then
  # Using sudo to install globally
  $SUDO npm install -g @google/gemini-cli
else
  info "Gemini CLI already installed."
fi

info "Setting up Oh My Zsh..."
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
  CHSH=no RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  info "Oh My Zsh already installed."
fi

info "Setting up Powerlevel10k..."
ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
  
  if [ -f "$USER_HOME/.zshrc" ]; then
    # Modify the default robbyrussell theme to powerlevel10k
    sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$USER_HOME/.zshrc"
  fi
else
  info "Powerlevel10k already installed."
fi

info "Installing Roboto Nerd Font..."
FONT_DIR="$USER_HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ ! -f "$FONT_DIR/RobotoMonoNerdFont-Regular.ttf" ]; then
  wget -nv -O /tmp/RobotoMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.zip
  unzip -q -o /tmp/RobotoMono.zip -d "$FONT_DIR"
  rm /tmp/RobotoMono.zip
  fc-cache -fv
else
  info "Roboto Nerd Font already installed."
fi

info "Setting up LazyVim..."
if [ ! -d "$USER_HOME/.config/nvim" ]; then
  git clone https://github.com/LazyVim/starter "$USER_HOME/.config/nvim"
  rm -rf "$USER_HOME/.config/nvim/.git"
else
  info "Neovim config already exists. Skipping LazyVim setup."
fi

info "Setting Zsh as default shell..."
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
  info "Changing shell to zsh for $USER_NAME..."
  $SUDO chsh -s "$ZSH_PATH" "$USER_NAME"
else
  info "Zsh is already the default shell."
fi

info "Setup complete! Please restart your terminal or re-login for the default shell and font changes to take effect."
