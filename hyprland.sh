#!/bin/zsh
# installing fonts
sudo pacman -S --noconfirm adobe-source-code-pro-fonts noto-fonts-emoji otf-font-awesome ttf-droid ttf-fira-code ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-ubuntu-font-family

# Update system
echo "Updating system..."
sudo pacman -Syu --noconfirm

# Install base packages
echo "Installing base packages..."
yay -S wlsunset --noconfirm --needed
sudo pacman -Sy htop pass os-prober firefox --noconfirm --needed

# Change time zone to Berlin
echo "Changing time zone to Europe/Berlin..."
sudo timedatectl set-timezone Europe/Berlin

# Create and configure the blue light filter script
echo "Creating blue light filter script..."
sudo mkdir -p /opt/sct
echo -e '#!/bin/sh\nkillall wlsunset &> /dev/null;\n\nif [ $# -eq 1 ]; then\n  temphigh=$(( $1 + 1 ))\n  templow=$1\n  wlsunset -t $templow -T $temphigh &> /dev/null &\nelse\n  killall wlsunset &> /dev/null;\nfi' | sudo tee /opt/sct/sct.sh > /dev/null
sudo chmod +x /opt/sct/sct.sh

# Add /opt/sct to PATH for Zsh
echo "Adding /opt/sct to PATH for Zsh..."
echo 'export PATH=$PATH:/opt/sct' >> ~/.zshrc
source ~/.zshrc

# Add Windows entry to GRUB
echo "Detecting other OS and updating GRUB..."
sudo os-prober
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Install and configure Hyprland theme
echo "Installing and configuring Hyprland theme..."
git clone --depth=1 https://github.com/JaKooLit/Arch-Hyprland ~/Arch-Hyprland
cd ~/Arch-Hyprland/ || exit
chmod +x install.sh
./install.sh

echo "Setup complete!"

