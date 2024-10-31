# installing fonts
sudo pacman -S --noconfirm adobe-source-code-pro-fonts noto-fonts-emoji otf-font-awesome ttf-droid ttf-fira-code ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-ubuntu-font-family

# enable bluthoot
sudo pacman -Sy --needed --noconfirm bluez bluez-utils blueman

sudo systemctl enable --now bluetooth.service

#installing audio and enable it
sudo pacman -Sy --needed --noconfirm pipewire wireplumber pipewire-audio pipewire-alsa pipewire-pulse sof-firmware

sudo systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
sudo systemctl --user enable --now pipewire.service
