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

# Cleanup potential broken file from previous failed run
if [ -f /etc/apt/sources.list.d/github-cli.sources ]; then
    info "Removing malformed GitHub CLI source file..."
    $SUDO rm /etc/apt/sources.list.d/github-cli.sources
fi

info "Updating and upgrading apt packages..."
$SUDO apt-get update -y
$SUDO apt-get upgrade -y

info "Installing base utilities and packages..."
$SUDO apt-get install -y \
  zsh \
  vim \
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
  ripgrep \
  fd-find \
  fontconfig

info "Setting Zsh as default shell..."
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
  info "Changing shell to zsh for $USER_NAME..."
  $SUDO chsh -s "$ZSH_PATH" "$USER_NAME"
else
  info "Zsh is already the default shell."
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
    sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$USER_HOME/.zshrc"
  fi
else
  info "Powerlevel10k already installed."
fi

info "Installing nvm and Node.js..."
export NVM_DIR="$USER_HOME/.nvm"
# Clean up any potential broken state or root-owned nvm directory
if [ -e "$NVM_DIR" ]; then
    $SUDO rm -rf "$NVM_DIR"
fi
$SUDO mkdir -p "$NVM_DIR"
$SUDO chown -R "$USER_NAME" "$NVM_DIR"

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# in lieu of restarting the shell
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Download and install Node.js:
nvm install 25

info "Installing Neovim..."
if ! command -v nvim &> /dev/null; then
  curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
  $SUDO rm -rf /opt/nvim-linux-x86_64
  $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
  rm nvim-linux-x86_64.tar.gz
  
  $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
else
  info "Neovim already installed."
fi

info "Installing GitHub CLI..."
if ! command -v gh &> /dev/null; then
  $SUDO mkdir -p -m 755 /etc/apt/keyrings
  GH_KEYRING_TMP=$(mktemp)
  wget -nv -O "$GH_KEYRING_TMP" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$GH_KEYRING_TMP" | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  
  # FIXED: Changed .sources to .list
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

read -p "Do you want to configure this installation as a Tailscale exit node? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  info "--- Starting Tailscale Exit Node & Optimization Setup ---"

  # 1. Enable IP Forwarding
  info "[1/5] Enabling IP forwarding..."
  $SUDO tee /etc/sysctl.d/99-tailscale.conf > /dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
  $SUDO sysctl -p /etc/sysctl.d/99-tailscale.conf

  # 2. Detect Network Interface and Subnet
  info "[2/5] Detecting local network settings..."
  # Finds the interface used for internet access (e.g., enp3s0 or eno1)
  NET_INTERFACE=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
  # Finds the local subnet associated with that interface (e.g., 192.168.1.0/24)
  SUBNET_ROUTE=$(ip route show dev "$NET_INTERFACE" | grep -v default | awk '{print $1}' | head -n 1)

  echo "    Found Interface: $NET_INTERFACE"
  echo "    Found Subnet:    $SUBNET_ROUTE"

  # 3. Apply UDP GRO Forwarding Optimizations (Immediate)
  info "[3/5] Applying UDP performance optimizations..."
  if ! command -v ethtool >/dev/null 2>&1; then
      $SUDO apt-get update && $SUDO apt-get install -y ethtool
  fi
  $SUDO ethtool -K "$NET_INTERFACE" rx-udp-gro-forwarding on rx-gro-list off

  # 4. Make Optimizations Persistent
  info "[4/5] Creating persistence script for optimizations..."
  $SUDO mkdir -p /etc/networkd-dispatcher/routable.d/
  $SUDO tee /etc/networkd-dispatcher/routable.d/50-tailscale > /dev/null <<'EOF'
#!/bin/sh
NET_INTERFACE=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
if [ -n "$NET_INTERFACE" ]; then
    ethtool -K "$NET_INTERFACE" rx-udp-gro-forwarding on rx-gro-list off || true
fi
EOF
  $SUDO chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

  # 5. Start Tailscale
  info "[5/5] Activating Tailscale..."
  $SUDO tailscale up --advertise-exit-node --advertise-routes="$SUBNET_ROUTE" --accept-routes

  info "--- Setup Complete! ---"
  info "Final Step: Go to the Tailscale Admin Console to approve the exit node and routes."
fi

info "Installing Gemini CLI..."
if ! command -v gemini &> /dev/null; then
  npm install -g @google/gemini-cli
else
  info "Gemini CLI already installed."
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


info "Setup complete! Please restart your terminal or re-login for the default shell and font changes to take effect."
