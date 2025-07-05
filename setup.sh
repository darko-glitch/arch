#!/bin/bash

# Exit on any error
set -e

echo "Starting Arch Linux setup..."

# Configure Pacman for better performance and visual feedback
echo "Optimizing pacman configuration..."
CONF="/etc/pacman.conf"

# Create backup of original configuration
echo "Creating backup of pacman.conf..."
sudo cp "$CONF" "$CONF.backup-$(date +%Y%m%d-%H%M%S)"

# Enable Color and ILoveCandy (Pac-Man progress bar)
echo "Enabling pacman colors and progress animation..."
if grep -q "^#Color" "$CONF"; then
    sudo sed -i 's/^#Color$/Color\nILoveCandy/' "$CONF"
else
    echo "Color already enabled in pacman.conf"
fi

# Set ParallelDownloads to CPU cores + 1 for faster downloads
CORES=$(($(nproc) + 1))
echo "Setting ParallelDownloads to $CORES (CPU cores + 1)..."
if grep -q "^#ParallelDownloads" "$CONF"; then
    sudo sed -i "s/^#ParallelDownloads = [0-9]*/ParallelDownloads = $CORES/" "$CONF"
else
    echo "ParallelDownloads already configured in pacman.conf"
fi

# Enable VerbosePkgLists for detailed package information
echo "Enabling verbose package lists..."
if grep -q "^#VerbosePkgLists" "$CONF"; then
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' "$CONF"
else
    echo "VerbosePkgLists already enabled in pacman.conf"
fi

echo "Pacman optimization complete!"

# Set GNOME desktop window button layout
echo "Configuring GNOME settings..."
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

# Allow volume above 100%
gsettings set org.gnome.desktop.sound allow-volume-above-100-percent 'true'

# Configure Night Light settings
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 12.0
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 11.9

# Install packages
echo "Installing packages..."
sudo pacman -S --noconfirm --needed \
    base-devel \
    git \
    zsh \
    wget \
    curl \
    firefox \
    unzip \
    pacman-contrib \
    ttf-ubuntu-font-family \
    libreoffice-fresh \
    ufw \
    flatpak \
    tk

# Enable and start essential services
echo "Configuring services..."
sudo systemctl enable --now paccache.timer ufw

# Configure Uncomplicated Firewall (UFW)
echo "Setting up firewall..."
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

# Install yay for managing AUR packages
echo "Installing yay AUR helper..."
mkdir -p ~/Downloads/Programs && cd ~/Downloads/Programs
if [ ! -d "yay" ]; then
    git clone https://aur.archlinux.org/yay.git
fi
cd yay
makepkg -si --noconfirm

# Install VSCodium from AUR
echo "Installing VSCodium..."
yay -S --noconfirm vscodium-bin

# Update xdg-user-dirs for user directories
xdg-user-dirs-update

# Set up Zsh configuration
echo "Configuring Zsh..."
if [ -f ~/arch/zshrc ]; then
    mv ~/arch/zshrc ~/.zshrc
    echo "Zsh configuration applied"
else
    echo "Warning: ~/arch/zshrc not found, using default zsh configuration"
fi

# Change shell to zsh
chsh -s /bin/zsh

# Update system packages
echo "Updating system..."
sudo pacman -Syu --noconfirm

# Power Management Setup
echo "Setting up power management..."

# Install TLP
echo "Installing TLP..."
sudo pacman -S --noconfirm --needed tlp

# Enable and start TLP service
echo "Enabling and starting TLP service..."
sudo systemctl enable --now tlp

# Install auto-cpufreq
CLONE_DIR=~/Downloads/auto-cpufreq/
echo "Installing auto-cpufreq..."

# Create Downloads directory if it doesn't exist
mkdir -p ~/Downloads

# Clone the repository (remove existing if present)
if [ -d "$CLONE_DIR" ]; then
    echo "Removing existing auto-cpufreq directory..."
    rm -rf "$CLONE_DIR"
fi

echo "Cloning the auto-cpufreq repository..."
git clone https://github.com/AdnanHodzic/auto-cpufreq.git "$CLONE_DIR"

# Verify the installer exists and is executable
if [ -f "$CLONE_DIR/auto-cpufreq-installer" ]; then
    echo "Running auto-cpufreq installer..."
    sudo "$CLONE_DIR/auto-cpufreq-installer"
else
    echo "Error: auto-cpufreq-installer not found in $CLONE_DIR"
    echo "Please check the repository structure manually"
fi

# Install pyenv
echo "Installing pyenv..."
if [ ! -d "$HOME/.pyenv" ]; then
    curl -fsSL https://pyenv.run | bash
fi

# Add pyenv to zshrc if not already present (for future shell sessions)
if ! grep -q "PYENV_ROOT" ~/.zshrc 2>/dev/null; then
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
    echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
    echo 'eval "$(pyenv init - zsh)"' >> ~/.zshrc
fi

# Set up pyenv environment for current script session
echo "Configuring pyenv environment..."
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# Initialize pyenv in current script
eval "$(pyenv init - bash)"

# Verify pyenv is working
if ! command -v pyenv >/dev/null 2>&1; then
    echo "Error: pyenv installation failed"
    exit 1
fi

echo "pyenv version: $(pyenv --version)"

# Install Python 3.13
echo "Installing Python 3.13..."
pyenv install -s 3.13  # -s flag skips if already installed

# Set Python 3.13 as global default
echo "Setting Python 3.13 as global default..."
pyenv global 3.13

# Verify Python installation
echo "Python version: $(python --version)"
echo "Python path: $(which python)"

# Create MCP directories
echo "Creating MCP directories..."
mkdir -p ~/.mcp/manually
if [ ! -d ~/.mcp/python ]; then
    python -m venv ~/.mcp/python
fi

# Install Node Version Manager (nvm)
echo "Installing nvm..."
if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi

echo "Setup complete!"
echo "Please run the following to reload your shell environment:"
echo "source ~/.zshrc"
echo "Then you can install Node.js with: nvm install node"