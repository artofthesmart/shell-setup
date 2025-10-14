#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
# Treat unset variables as an error
set -u
# Enable the errexit option for pipelines
set -o pipefail

echo "Starting Ubuntu zsh setup script..."

# --- Task 1: Update and Upgrade Packages ---
echo ""
echo "--- Updating and upgrading system packages ---"
# Use apt for Ubuntu
sudo apt update -y || { echo "ERROR: apt update failed."; exit 1; }
sudo apt upgrade -y || { echo "ERROR: apt upgrade failed."; exit 1; }
echo "--- Package update and upgrade complete ---"

# --- Task 2: Install Required Packages ---
echo ""
echo "--- Installing core packages ---"
# Use apt for Ubuntu and ensure curl is included for Oh-My-Zsh installation
PACKAGES="man neovim wget python3 zsh git gitui mc curl"
echo "Installing: $PACKAGES"
# Use sudo apt install for system-wide package installation
sudo apt install -y $PACKAGES || { echo "ERROR: apt install failed."; exit 1; }
echo "--- Core packages installation complete ---"

# --- Task 3: Install Oh-My-Zsh ---
echo ""
echo "--- Installing Oh-My-Zsh ---"
# Use the unattended install to avoid prompts and not change the default shell immediately
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Cloning Oh-My-Zsh repository..."
  # The "" argument is for the optional repo path, --unattended skips interactive prompts
  # Note: curl must be installed in Task 2 for this to work
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || { echo "ERROR: Oh-My-Zsh installation failed."; exit 1; }
  echo "--- Oh-My-Zsh installation complete ---"
  echo "Oh-My-Zsh is installed, but your default shell is likely still bash."
  echo "To switch to zsh, run 'chsh -s \$(which zsh)' and re-login/reboot."
else
  echo "Oh-My-Zsh directory already exists ($HOME/.oh-my-zsh). Skipping installation."
  echo "If you need to update Oh-My-Zsh, open a zsh shell and run 'omz update'."
fi

# --- Task 4: Install and Configure Powerlevel10k ---
echo ""
echo "--- Installing Powerlevel10k ---"
# Clone Powerlevel10k into the custom themes directory
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
  echo "Cloning Powerlevel10k repository..."
  # ZSH_CUSTOM is likely unset, so it defaults to $HOME/.oh-my-zsh/custom/themes/powerlevel10k
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" || { echo "ERROR: Failed to clone Powerlevel10k."; exit 1; }
  echo "--- Powerlevel10k cloning complete ---"

  echo "Setting ZSH_THEME to powerlevel10k/powerlevel10k in ~/.zshrc"
  # Use sed to find the line starting with ZSH_THEME= and replace it
  # Using # as a delimiter in sed to avoid issues with / in the path
  sed -i 's#^ZSH_THEME=".*"#ZSH_THEME="powerlevel10k/powerlevel10k"#' "$HOME/.zshrc" || { echo "ERROR: Failed to update ZSH_THEME in ~/.zshrc."; exit 1; }
  echo "--- ZSH_THEME updated ---"
else
  echo "Powerlevel10k directory already exists. Skipping cloning and .zshrc modification."
fi

# --- Task 5: Skip Nerd Font Installation for Ubuntu ---
# In Ubuntu, font installation is managed at the desktop environment level.
# The user needs to manually install a Nerd Font on their system
# (e.g., via the system's font manager or by downloading and double-clicking).
# The Termux-specific settings for fonts and extra-keys are removed.
# Example for a user-specific Nerd Font installation
FONT_DIR="$HOME/.local/share/fonts"
NERD_FONT_ZIP_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/RobotoMono.zip"

# Download, extract, and clean up
mkdir -p "$FONT_DIR/RobotoMono"
wget -P /tmp "$NERD_FONT_ZIP_URL"
unzip /tmp/RobotoMono.zip -d "$FONT_DIR/RobotoMono"
rm /tmp/RobotoMono.zip

echo ""
echo "--- Font Configuration Note ---"
echo "Nerd Font installation is installed for Ubuntu for only your user."
echo "For Powerlevel10k to display correctly, you must **manually** select a Nerd Font"
echo "and then set that font in your terminal application's settings."
echo "-------------------------------"

# --- Task 6: Install LazyVim ---
echo ""
echo "--- Installing LazyVim ---"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

mkdir -p "$HOME/.config" || { echo "ERROR: Failed to create directory $HOME/.config."; exit 1; }

if [ -d "$NVIM_CONFIG_DIR" ]; then
  echo "WARNING: Existing Neovim configuration found at $NVIM_CONFIG_DIR."
  read -p "Do you want to remove the existing config and install LazyVim? (y/N): " confirm_lazyvim
  if [[ "$confirm_lazyvim" != "y" && "$confirm_lazyvim" != "Y" ]]; then
    echo "Skipping LazyVim installation as requested."
  else
    echo "Removing existing Neovim configuration..."
    rm -rf "$NVIM_CONFIG_DIR" || { echo "ERROR: Failed to remove existing Neovim config."; exit 1; }
    echo "Existing config removed. Cloning LazyVim starter..."
    git clone https://github.com/LazyVim/starter "$NVIM_CONFIG_DIR" || { echo "ERROR: Failed to clone LazyVim starter."; exit 1; }
    echo "Removing .git directory from LazyVim starter..."
    rm -rf "$NVIM_CONFIG_DIR/.git" || { echo "ERROR: Failed to remove .git from LazyVim starter."; exit 1; }
    echo "--- LazyVim installation process started ---"
    echo "Run 'nvim' to open Neovim and complete the LazyVim setup (it will download plugins)."
  fi
else
  echo "No existing Neovim configuration found. Cloning LazyVim starter..."
  git clone https://github.com/LazyVim/starter "$NVIM_CONFIG_DIR" || { echo "ERROR: Failed to clone LazyVim starter."; exit 1; }
  echo "Removing .git directory from LazyVim starter..."
  rm -rf "$NVIM_CONFIG_DIR/.git" || { echo "ERROR: Failed to remove .git from LazyVim starter."; exit 1; }
  echo "--- LazyVim installation process started ---"
  echo "Run 'nvim' to open Neovim and complete the LazyVim setup (it will download plugins)."
fi


echo ""
echo "--------------------------------------------------"
echo "Ubuntu zsh setup script finished."
echo "Recommendations:"
echo "1. If you want **zsh as your default shell**, run **'chsh -s \$(which zsh)'** and then **log out and log back in** (or reboot)."
echo "2. Run **'nvim'** to start Neovim and let LazyVim install its plugins."
echo "3. Once you're in a zsh shell, run **'p10k configure'** to set up Powerlevel10k's appearance."
echo "4. You must **manually install a Nerd Font** on your Ubuntu system and configure your terminal emulator to use it for Powerlevel10k to look right."
echo "--------------------------------------------------"

exit 0
