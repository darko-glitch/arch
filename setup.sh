#!/bin/bash

# Set GNOME desktop window button layout
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

# Allow volume above 100%
gsettings set org.gnome.desktop.sound allow-volume-above-100-percent 'true'

# Configure Night Light settings
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 12.0
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 11.9

# Install necessary packages
sudo pacman -S --noconfirm enchant gnome-tweaks corectrl mythes-en ttf-liberation hunspell-en_US ttf-bitstream-vera pkgstats adobe-source-sans-pro-fonts gst-plugins-good ttf-droid ttf-dejavu aspell-en icedtea-web gst-libav ttf-ubuntu-font-family ttf-anonymous-pro jre8-openjdk languagetool p7zip unrar tar gedit a52dec faac faad2 flac jasper lame libdca libdv libmad libmpeg2 libtheora libvorbis libxv wavpack x264 xvidcore ufw amd-ucode libmythes pacman-contrib xdg-user-dirs base-devel git gdm gnome-backgrounds gnome-color-manager gnome-console gnome-disk-utility gnome-shell gnome-shell-extensions gnome-system-monitor gedit xorg-server xorg-xinit gnome-shell nautilus gnome-terminal guake gnome-control-center xdg-user-dirs gdm networkmanager zsh wget gnome-browser-connector

sudo systemctl enable gdm.service
sudo systemctl enable NetworkManager
# Configure Uncomplicated Firewall (UFW)
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Enable paccache timer for package cache cleanup
sudo systemctl enable paccache.timer

# Install yay for managing AUR packages
mkdir -p ~/Programs && cd ~/Programs
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Install brave-bin package using yay
yay -S --noconfirm brave-bin

# Update xdg-user-dirs for user directories
xdg-user-dirs-update

# Clone and apply Kali Linux themes
cd ~/Downloads
git clone https://gitlab.com/kalilinux/packages/kali-themes.git
sudo mv -f kali-themes/share/themes/Kali* /usr/share/themes/
sudo mv -f kali-themes/share/icons/* /usr/share/icons/
sudo mv -f kali-themes/share/* /usr/share/
sudo mv -f kali-themes/share/backgrounds/* /usr/share/backgrounds
sudo mv -f kali-themes/share/gtksourceview-4/styles/* /usr/share/gtksourceview-4/styles
sudo chmod 755 $(sudo find /usr/share/themes/Kali* -type d)
sudo chmod 644 $(sudo find /usr/share/themes/Kali* -type f)
sudo chmod 755 $(sudo find /usr/share/icons/Flat* -type d)
sudo chmod 644 $(sudo find /usr/share/icons/Flat* -type f)
sudo gtk-update-icon-cache /usr/share/icons/Flat-Remix-Blue-Dark/

# Set up Zsh configuration
mv ~/arch/zshrc ~/.zshrc
chsh -s /bin/zsh
autoload -Uz compinit promptinit

# Copy Kali Linux color scheme for qtermwidget
sudo cp ~/Downloads/kali-themes/share/qtermwidget5/color-schemes/Kali-Dark.colorscheme /usr/share/qtermwidget5/color-schemes/Kali-Dark.colorscheme

# Clean up cloned repository
rm -rf kali-themes

# Install Miniconda for Python package management
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/Downloads/miniconda.sh
bash ~/Downloads/miniconda.sh -b -p $HOME/miniconda
eval "$($HOME/miniconda/bin/conda shell.bash hook)"
conda init

# Update Conda and create a Python environment named 'ai'
conda update --all -y
conda create -y -n ai python spyder notebook
conda activate ai

# Install TensorFlow for ROCm
pip install tensorflow-rocm

# Clone and install LACT (Lightweight Accelerated Cell Trajectory inference)
git clone https://github.com/ilya-zlobintsev/LACT && cd LACT
make
sudo make install

# Configure Uncomplicated Firewall (UFW) again
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Update system packages
sudo pacman -Syu --noconfirm

