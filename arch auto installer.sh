#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function for checking partition existence
check_partition() {
    if [ ! -e "$1" ]; then
        echo "Error: Partition $1 does not exist."
        exit 1
    fi
}

echo "Please enter EFI partition: (example /dev/sda1 or /dev/nvme0n1p1)"
read EFI
check_partition "$EFI"

echo "Please enter Root(/) partition: (example /dev/sda2 or /dev/nvme0n1p2)"
read ROOT
check_partition "$ROOT"

echo "Please enter your Username"
read USER

echo "Please enter your Full Name"
read NAME

echo "Please enter your Password"
read -s PASSWORD  # Silent input for password

# Choose filesystem
echo "Select filesystem type:"
echo "1. ext4"
echo "2. btrfs"
read -p "Enter your choice (1 or 2): " FS_CHOICE

# Make filesystems
echo -e "\nCreating Filesystems...\n"

if [[ "$FS_CHOICE" == "1" ]]; then
    mkfs.ext4 "${ROOT}"
elif [[ "$FS_CHOICE" == "2" ]]; then
    mkfs.btrfs "${ROOT}"

    # Create btrfs subvolumes
    mount "${ROOT}" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    # Mount subvolumes with compression
    mount -o compress=zstd,subvol=@ "${ROOT}" /mnt
    mkdir -p /mnt/home /mnt/var /mnt/tmp
    mount -o compress=zstd,subvol=@home "${ROOT}" /mnt/home
    mount -o compress=zstd,subvol=@var "${ROOT}" /mnt/var
    mount -o compress=zstd,subvol=@tmp "${ROOT}" /mnt/tmp

    # Ask about snapshots
    read -p "Do you want to make snapshots? (y/n) " SNAPSHOT_CHOICE
    if [[ "$SNAPSHOT_CHOICE" == "y" ]]; then
        mkdir -p /mnt/.snapshots 
        mount -o compress=zstd,subvol=@snapshots "${ROOT}" /mnt/.snapshots
    fi
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Mount EFI partition
mkdir -p /mnt/efi
mount "${EFI}" /mnt/efi

echo -e "\nUpdating mirrorlist with reflector...\n"
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

echo "--------------------------------------"
echo "-- INSTALLING Base Arch Linux --"
echo "--------------------------------------"
pacstrap /mnt base base-devel linux linux-firmware linux-headers iwd dhcpcd nano bluez bluez-utils git --noconfirm --needed

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

cat <<REALEND > /mnt/next.sh
#!/bin/bash

# Enable multilib repository
echo -e "\nEnabling multilib repository...\n"
cat << EOF >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

# User creation and system configuration
useradd -m -b /home -G wheel,storage,power,audio,video "$USER"
usermod -c "$NAME" "$USER"
echo "$USER:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Locale and timezone settings
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

# Hostname and hosts configuration
echo "archlinux" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 archlinux.localdomain archlinux
EOF

# Bootloader installation
pacman -S grub ntfs-3g os-prober efibootmgr --noconfirm --needed
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Video driver selection
echo "Select video driver:"
echo "1. AMD"
echo "2. Intel"
echo "3. NVIDIA"
read -p "Enter your choice (1, 2, or 3): " VIDEO_CHOICE

case "\$VIDEO_CHOICE" in
    1) pacman -S vulkan-amdgpu mesa xf86-video-amdgpu --noconfirm --needed ;;
    2) pacman -S xorg mesa xf86-video-intel --noconfirm --needed ;;
    3) pacman -S xorg mesa nvidia nvidia-utils nvidia-settings opencl-nvidia nvidia-prime --noconfirm --needed ;;
    *) echo "Invalid video driver choice." ; exit 1 ;;
esac

# Audio driver selection
echo "Select audio driver:"
echo "1. PipeWire"
echo "2. PulseAudio"
read -p "Enter your choice (1 or 2): " AUDIO_CHOICE

case "\$AUDIO_CHOICE" in
    1) pacman -S pipewire pipewire-alsa pipewire-pulse --noconfirm --needed
       systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service
       systemctl --user enable pipewire.service ;;
    2) pacman -S pulseaudio pulseaudio-alsa --noconfirm --needed
       systemctl enable pulseaudio ;;
    *) echo "Invalid audio driver choice." ; exit 1 ;;
esac

# Choose Desktop Environment
echo "Select Desktop Environment:"
echo "1. GNOME"
echo "2. Hyprland"
echo "3. XFCE"
echo "4. BSPWM"
read -p "Enter your choice (1, 2, 3, or 4): " DE_CHOICE

case "\$DE_CHOICE" in
    1) pacman -S gnome-shell gnome-control-center gnome-calculator gnome-menus colord-gtk nautilus python-nautilus ffmpegthumbnailer gvfs-mtp file-roller xdg-desktop-portal-gnome gnome-tweaks gnome-terminal gnome-themes-extra gnome-color-manager gnome-backgrounds gnome-disk-utility gnome-screenshot gnome-shell-extensions evince loupe gnome-text-editor xdg-user-dirs-gtk --noconfirm --needed
       pacman -S ttf-liberation ttf-fira-sans ttf-jetbrains-mono noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra --noconfirm --needed ;;
    2) pacman -S hyprland hyprcursor hyprutils thunar xdg-desktop-portal-hyprland xdg-desktop-portal-gtk thunar-volman tumbler ffmpegthumbnailer file-roller thunar-archive-plugin aquamarine hypridle hyprlock pyprland aylurs-gtk-shell cliphist kvantum rofi-wayland imagemagick swaync swww wallust waybar wl-clipboard wlogout kitty --noconfirm --needed
       pacman -Rns dunst mako rofi wallust-git ;;
    3) pacman -S xfce4 xfce4-goodies --noconfirm --needed ;;
    4) pacman -S bspwm sxhkd polybar dmenu rofi nitrogen picom --noconfirm --needed ;;
    *) echo "Invalid desktop environment choice." ; exit 1 ;;
esac

# Display Manager Selection
echo "Select Display Manager:"
echo "1. GDM"
echo "2. LY"
echo "3. SDDM"
read -p "Enter your choice (1, 2, or 3): " DM_CHOICE

case "\$DM_CHOICE" in
    1) pacman -S gdm --noconfirm --needed
       systemctl enable gdm ;;
    2) pacman -S ly --noconfirm --needed
       systemctl enable ly ;;
    3) pacman -S sddm qt6-svg --noconfirm --needed
       systemctl enable sddm ;;
    *) echo "Invalid display manager choice. No display manager will be enabled." ;;
esac

# Additional software installation
pacman -S wget vlc neofetch switcheroo-control --noconfirm --needed
systemctl enable switcheroo-control

echo "-------------------------------------------------"
echo "Install Complete, You can reboot now"
echo "-------------------------------------------------"
REALEND


arch-chroot /mnt sh next.sh
