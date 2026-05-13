#!/bin/bash
# =============================================================================
# Antigravity Linux Environment Setup Script
# =============================================================================
# Reconstructs this Linux environment from scratch on a fresh Ubuntu install.
# Run with: curl -S https://raw.githubusercontent.com/artofthesmart/shell-setup/refs/heads/main/bash.sh | bash
#
# BREAKPOINTS: For "extra" installations, the script will pause and ask
# before proceeding — so you can skip sections safely on future runs.
# =============================================================================

set -e  # Exit immediately if a command fails

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
info()    { echo -e "\e[32m[INFO]\e[0m  $1"; }
warn()    { echo -e "\e[33m[WARN]\e[0m  $1"; }
section() { echo -e "\n\e[1;34m========================================\e[0m"; \
            echo -e "\e[1;34m  $1\e[0m"; \
            echo -e "\e[1;34m========================================\e[0m"; }

# Ask user if they want to proceed with an optional section.
# Usage: ask_proceed "Section description"
# Returns 0 (yes) or 1 (no).
ask_proceed() {
    echo ""
    read -p "  ⚙️  BREAKPOINT — Install: $1? [y/N] " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# Privilege check
# -----------------------------------------------------------------------------
SUDO=''
if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO='sudo'
        # Cache sudo credentials upfront so we don't get prompted mid-script
        sudo -v
    else
        warn "You are not root and sudo is not available. Please run as root."
        exit 1
    fi
fi

USER_HOME="$HOME"
USER_NAME="$(whoami)"


# =============================================================================
# SECTION 1: Base APT Packages & System Update
# These are always installed — no breakpoint.
# =============================================================================
section "1/11  Base System Utilities"

# Remove a known-bad source file that breaks GH CLI installs
if [ -f /etc/apt/sources.list.d/github-cli.sources ]; then
    info "Removing malformed GitHub CLI source file..."
    $SUDO rm /etc/apt/sources.list.d/github-cli.sources
fi

info "Updating and upgrading APT packages..."
$SUDO apt-get update -y
$SUDO apt-get upgrade -y

info "Installing base utilities..."
$SUDO apt-get install -y \
    zsh vim python3 python3-pip python3-venv \
    gpg make man-db gcc unzip wget curl git \
    ripgrep fd-find fontconfig ethtool \
    ca-certificates ufw ncdu htop btop

info "Enabling UFW firewall..."
$SUDO ufw enable || true   # 'true' prevents set -e from firing if already enabled


# =============================================================================
# SECTION 2: Zsh + Oh My Zsh + Powerlevel10k + Plugins
# Core shell setup — always installed.
# =============================================================================
section "2/11  Zsh Shell & Prompt"

info "Setting Zsh as the default shell..."
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
    $SUDO chsh -s "$ZSH_PATH" "$USER_NAME"
else
    info "Zsh is already the default shell."
fi

info "Installing Oh My Zsh..."
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    CHSH=no RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    info "Oh My Zsh already installed."
fi

info "Installing Powerlevel10k theme..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}"
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "$ZSH_CUSTOM/themes/powerlevel10k"
    if [ -f "$USER_HOME/.zshrc" ]; then
        sed -i 's/ZSH_THEME=".*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' "$USER_HOME/.zshrc"
    fi
else
    info "Powerlevel10k already installed."
fi

info "Installing Zsh plugins (autosuggestions + syntax-highlighting)..."
PLUGINS_DIR="$ZSH_CUSTOM/plugins"
if [ ! -d "$PLUGINS_DIR/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        "$PLUGINS_DIR/zsh-autosuggestions"
fi
if [ ! -d "$PLUGINS_DIR/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
        "$PLUGINS_DIR/zsh-syntax-highlighting"
fi
# Enable plugins in .zshrc
if [ -f "$USER_HOME/.zshrc" ]; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/g' \
        "$USER_HOME/.zshrc" || true
fi

info "Installing Roboto Mono Nerd Font..."
FONT_DIR="$USER_HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ ! -f "$FONT_DIR/RobotoMonoNerdFont-Regular.ttf" ]; then
    wget -nv -O /tmp/RobotoMono.zip \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.zip
    unzip -q -o /tmp/RobotoMono.zip -d "$FONT_DIR"
    rm /tmp/RobotoMono.zip
    fc-cache -fv
else
    info "Roboto Nerd Font already installed."
fi

# After p10k is installed, run the interactive configurator on first login.
# The user should run: p10k configure


# =============================================================================
# SECTION 3: Build Essentials
# Required for compiling Python extensions, native modules, etc.
# =============================================================================
section "3/11  Build Essentials & Python Dev Libraries"

info "Installing build-essential and dev libraries..."
$SUDO apt-get install -y \
    build-essential libssl-dev libffi-dev libncurses5-dev \
    zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    llvm libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev liblzma-dev


# =============================================================================
# SECTION 4: Python uv (fast package manager)
# =============================================================================
section "4/11  Python uv"

if ! command -v uv &>/dev/null; then
    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Ensure uv is on PATH for this session and future sessions
    export PATH="$HOME/.local/bin:$PATH"
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$USER_HOME/.zshrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.zshrc"
    fi
else
    info "uv already installed ($(uv --version))."
fi


# =============================================================================
# SECTION 5: GitHub CLI (gh)
# =============================================================================
section "5/11  GitHub CLI"

if ! command -v gh &>/dev/null; then
    info "Installing GitHub CLI..."
    $SUDO mkdir -p -m 755 /etc/apt/keyrings
    GH_KEYRING_TMP=$(mktemp)
    wget -nv -O "$GH_KEYRING_TMP" https://cli.github.com/packages/githubcli-archive-keyring.gpg
    cat "$GH_KEYRING_TMP" | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    $SUDO apt-get update -y
    $SUDO apt-get install gh -y
    rm -f "$GH_KEYRING_TMP"
    info "GitHub CLI installed. Run: gh auth login"
else
    info "GitHub CLI already installed."
fi


# =============================================================================
# SECTION 6: Neovim + LazyVim
# =============================================================================
section "6/11  Neovim & LazyVim"

if ! command -v nvim &>/dev/null; then
    info "Installing Neovim (latest binary)..."
    curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    $SUDO rm -rf /opt/nvim-linux-x86_64
    $SUDO tar -C /opt -xzf nvim-linux-x86_64.tar.gz
    rm nvim-linux-x86_64.tar.gz
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
else
    info "Neovim already installed."
fi

info "Setting up LazyVim starter config..."
NVIM_CONFIG="$USER_HOME/.config/nvim"
if [ ! -d "$NVIM_CONFIG" ]; then
    git clone https://github.com/LazyVim/starter "$NVIM_CONFIG"
    rm -rf "$NVIM_CONFIG/.git"
else
    info "Neovim config already exists — skipping LazyVim clone."
fi


# =============================================================================
# SECTION 7: Node.js via NVM
# =============================================================================
section "7/11  Node.js via NVM"

if ! command -v node &>/dev/null; then
    info "Installing NVM and Node.js 22 LTS..."
    export NVM_DIR="$USER_HOME/.nvm"
    [ -d "$NVM_DIR" ] && $SUDO rm -rf "$NVM_DIR"
    $SUDO mkdir -p "$NVM_DIR"
    $SUDO chown -R "$USER_NAME" "$NVM_DIR"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
else
    info "Node.js already installed ($(node --version))."
fi


# =============================================================================
# SECTION 8: Antigravity IDE
# Breakpoint — skip if already installed or not needed.
# =============================================================================
section "8/11  Antigravity IDE"

if ask_proceed "Antigravity IDE (apt package)"; then
    if ! command -v antigravity &>/dev/null; then
        info "Installing Antigravity..."
        $SUDO mkdir -p /etc/apt/keyrings
        curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
            | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
        echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
            | $SUDO tee /etc/apt/sources.list.d/antigravity.list >/dev/null
        $SUDO apt-get update -y
        $SUDO apt-get install -y antigravity
    else
        info "Antigravity already installed."
    fi
else
    info "Skipping Antigravity."
fi


# =============================================================================
# SECTION 9: Tailscale + Exit Node Configuration
# Breakpoint — configure as exit node only when needed.
# =============================================================================
section "9/11  Tailscale VPN"

if ask_proceed "Tailscale VPN"; then
    if ! command -v tailscale &>/dev/null; then
        info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        info "Tailscale already installed."
    fi

    # --- Tailscale Exit Node sub-breakpoint ---
    if ask_proceed "  Configure as Tailscale Exit Node (with subnet routing)"; then
        info "[1/5] Enabling IP forwarding..."
        $SUDO tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
        $SUDO sysctl -p /etc/sysctl.d/99-tailscale.conf

        info "[2/5] Detecting local network settings..."
        NET_INTERFACE=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
        SUBNET_ROUTE=$(ip route show dev "$NET_INTERFACE" | grep -v default | awk '{print $1}' | head -n 1)
        echo "    Interface: $NET_INTERFACE  |  Subnet: $SUBNET_ROUTE"

        info "[3/5] Applying UDP GRO forwarding optimizations..."
        $SUDO ethtool -K "$NET_INTERFACE" rx-udp-gro-forwarding on rx-gro-list off

        info "[4/5] Making optimizations persistent via networkd-dispatcher..."
        $SUDO mkdir -p /etc/networkd-dispatcher/routable.d/
        # Write the persistence script — uses dynamic interface detection at boot
        printf '#!/bin/sh\nNET_INTERFACE=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")\nif [ -n "$NET_INTERFACE" ]; then\n    ethtool -K "$NET_INTERFACE" rx-udp-gro-forwarding on rx-gro-list off || true\nfi\n' \
            | $SUDO tee /etc/networkd-dispatcher/routable.d/50-tailscale >/dev/null
        $SUDO chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

        info "[5/5] Activating Tailscale as exit node..."
        $SUDO tailscale up \
            --advertise-exit-node \
            --advertise-routes="$SUBNET_ROUTE" \
            --accept-routes || true

        warn "Go to Tailscale Admin Console to approve the exit node and routes."
    fi

    # Enable systray for desktop sessions
    if ask_proceed "  Enable Tailscale systray (desktop autostart)"; then
        tailscale configure systray --enable-startup systemd || true
        systemctl --user daemon-reload || true
        systemctl --user enable --now tailscale-systray || true
        info "Set the Tailscale operator so systray works without sudo:"
        info "  sudo tailscale set --operator=\$USER"
    fi
else
    info "Skipping Tailscale."
fi


# =============================================================================
# SECTION 10: Docker Engine + NVIDIA Container Toolkit + AI Infrastructure
# Major breakpoint — this installs Docker (official), NVIDIA toolkit, and
# sets up the AI model storage layout.
# =============================================================================
section "10/11  Docker & AI Infrastructure"

if ask_proceed "Docker Engine (official docker.com packages)"; then
    if ! command -v docker &>/dev/null; then
        info "Adding Docker's official GPG key and APT repository..."
        $SUDO apt-get install -y ca-certificates curl
        $SUDO install -m 0755 -d /etc/apt/keyrings
        $SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        $SUDO chmod a+r /etc/apt/keyrings/docker.asc

        $SUDO tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        $SUDO apt-get update -y
        $SUDO apt-get install -y \
            docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin

        info "Adding $USER_NAME to the docker group..."
        $SUDO usermod -aG docker "$USER_NAME"

        info "Enabling Docker service..."
        $SUDO systemctl enable docker
        $SUDO systemctl start docker

        info "Testing Docker install..."
        $SUDO docker run --rm hello-world
    else
        info "Docker already installed ($(docker --version))."
    fi

    # --- NVIDIA Container Toolkit sub-breakpoint ---
    if ask_proceed "  NVIDIA Container Toolkit (for GPU passthrough to Docker)"; then
        info "Installing NVIDIA Container Toolkit..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | $SUDO gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            | $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        $SUDO apt-get update -y
        $SUDO apt-get install -y nvidia-container-toolkit
        $SUDO nvidia-ctk runtime configure --runtime=docker
        $SUDO systemctl restart docker
        info "NVIDIA Container Toolkit installed and Docker restarted."
    fi

    # --- AI model storage directories sub-breakpoint ---
    if ask_proceed "  Create AI model storage directories (/var/lib/ai-models)"; then
        # These paths match the volume mounts in docker-compose.yaml:
        #   /var/lib/ai-models/ollama/gpu-root  -> ollama-gpu container root
        #   /var/lib/ai-models/ollama/cpu-root  -> ollama-cpu container root
        #   /var/lib/ai-models/ollama/blobs     -> shared binary blobs (both ollama instances)
        #   /var/lib/ai-models/llama            -> llama.cpp model files
        $SUDO mkdir -p \
            /var/lib/ai-models/ollama/gpu-root \
            /var/lib/ai-models/ollama/cpu-root \
            /var/lib/ai-models/ollama/blobs \
            /var/lib/ai-models/llama
        $SUDO chown -R "$USER_NAME:$USER_NAME" /var/lib/ai-models
        info "AI model directories created and owned by $USER_NAME."
    fi

    # --- Clone & symlink shell-setup repo sub-breakpoint ---
    if ask_proceed "  Clone shell-setup repo and symlink docker-compose.yaml to home"; then
        mkdir -p "$USER_HOME/Github"
        if [ ! -d "$USER_HOME/Github/shell-setup" ]; then
            git clone https://github.com/artofthesmart/shell-setup.git \
                "$USER_HOME/Github/shell-setup"
        else
            info "shell-setup repo already cloned."
        fi

        # Symlink docker-compose.yaml to home so 'docker compose' works from ~
        if [ ! -e "$USER_HOME/docker-compose.yaml" ]; then
            ln -s "$USER_HOME/Github/shell-setup/docker-compose.yaml" \
                "$USER_HOME/docker-compose.yaml"
            info "Symlinked docker-compose.yaml to ~"
        fi

        # Symlink .env to home (contains TS_AUTH_KEY, HF_TOKEN, etc.)
        if [ ! -e "$USER_HOME/.env" ]; then
            ln -s "$USER_HOME/Github/shell-setup/.env" "$USER_HOME/.env"
            chmod 600 "$USER_HOME/Github/shell-setup/.env" 2>/dev/null || true
            info "Symlinked .env to ~"
        fi

        warn "Remember: populate .env with TS_AUTH_KEY, HF_TOKEN, LLAMA_* vars before starting containers."
        warn "Then run from ~: docker compose --profile manual up -d --remove-orphans"
    fi

else
    info "Skipping Docker."
fi


# =============================================================================
# SECTION 11: NVIDIA Drivers + CUDA Toolkit
# Breakpoint — only needed on machines with an NVIDIA GPU.
# =============================================================================
section "11/11  NVIDIA Drivers & CUDA Toolkit"

if ask_proceed "NVIDIA Drivers & CUDA Toolkit (requires NVIDIA GPU)"; then
    info "Adding NVIDIA PPA and installing recommended drivers..."
    $SUDO add-apt-repository ppa:graphics-drivers/ppa -y
    $SUDO apt-get update -y
    $SUDO ubuntu-drivers install

    info "Installing CUDA Toolkit..."
    $SUDO apt-get install -y nvidia-cuda-toolkit

    # Add CUDA paths to Zsh config permanently
    ZSHRC="$USER_HOME/.zshrc"
    if ! grep -q 'cuda/bin' "$ZSHRC" 2>/dev/null; then
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> "$ZSHRC"
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> "$ZSHRC"
    fi

    info "Verifying NVIDIA install..."
    nvidia-smi || warn "nvidia-smi failed — a reboot may be required."
    nvcc --version || warn "nvcc not in PATH yet — source .zshrc or reboot."
else
    info "Skipping NVIDIA drivers."
fi


# =============================================================================
# OPTIONAL EXTRAS (Breakpoint each)
# =============================================================================

# --- Gemini CLI ---
if ask_proceed "Gemini CLI (npm global install)"; then
    NVM_DIR="$USER_HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npm install -g @google/gemini-cli
    info "Run 'gemini' to start. Authenticate on first launch."
fi

# --- Flatpak + Flathub + Multimedia Codecs ---
if ask_proceed "Flatpak, Flathub, multimedia codecs & archive support"; then
    $SUDO apt-get install -y \
        flatpak gnome-software-plugin-flatpak \
        ubuntu-restricted-extras \
        fonts-crosextra-caladea fonts-crosextra-carlito \
        ffmpegthumbnailer \
        unrar p7zip-full p7zip-rar
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    warn "A reboot is recommended after adding Flathub."
fi

# --- GNOME Customization Tools ---
if ask_proceed "GNOME Tweaks & Extension Manager"; then
    $SUDO apt-get install -y gnome-tweaks gnome-shell-extension-manager
fi

# --- Steam ---
if ask_proceed "Steam (gaming)"; then
    info "Adding Steam repository and installing..."
    $SUDO dpkg --add-architecture i386
    $SUDO apt-get update -y
    wget -qO /tmp/steam.gpg https://repo.steampowered.com/steam/archive/stable/steam.gpg
    $SUDO cp /tmp/steam.gpg /usr/share/keyrings/steam.gpg
    rm /tmp/steam.gpg
    $SUDO tee /etc/apt/sources.list.d/steam-stable.list >/dev/null <<'EOF'
deb [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] https://repo.steampowered.com/steam/ stable steam
deb-src [arch=amd64,i386 signed-by=/usr/share/keyrings/steam.gpg] https://repo.steampowered.com/steam/ stable steam
EOF
    $SUDO apt-get update -y
    $SUDO apt-get install -y \
        libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
        libgl1:amd64 libgl1:i386 \
        steam-launcher
fi

# --- fzf (Fuzzy Finder) ---
if ask_proceed "fzf (fuzzy file finder)"; then
    if [ ! -d "$USER_HOME/.fzf" ]; then
        git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
        "$USER_HOME/.fzf/install" --all
    else
        info "fzf already installed."
    fi
fi

# --- bat (syntax-highlighted cat) ---
if ask_proceed "bat (syntax-highlighted cat replacement)"; then
    $SUDO apt-get install -y bat
    # On Ubuntu the binary is 'batcat' — alias it
    if ! grep -q "alias bat='batcat'" "$USER_HOME/.zshrc" 2>/dev/null; then
        echo "alias bat='batcat'" >> "$USER_HOME/.zshrc"
    fi
fi

# --- fastfetch ---
if ask_proceed "fastfetch (system info display)"; then
    $SUDO apt-get install -y fastfetch
fi

# --- VLC Media Player ---
if ask_proceed "VLC media player"; then
    $SUDO apt-get install -y vlc
fi


# =============================================================================
# POST-INSTALL SUMMARY
# =============================================================================
section "Setup Complete!"
echo ""
echo "  Next steps:"
echo "  1. Restart your terminal (or run: exec zsh)"
echo "  2. Run 'p10k configure' to set up your prompt theme"
echo "  3. Run 'gh auth login' to authenticate with GitHub"
echo "  4. If Docker was installed, log out and back in (for group membership)"
echo "  5. If NVIDIA drivers were installed, reboot the system"
echo "  6. Populate ~/Github/shell-setup/.env before starting containers"
echo ""
info "Done! Happy hacking. 🚀"
