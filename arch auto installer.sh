#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function for checking partition existence
check_partition() {
    if [ ! -e "$1" ]; then
        echo "Error: Partition $1 does not exist."
        exit 1
    fi
}

# User input for partitions
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

echo "--------------------------------------"
echo "--   Format and making partitions   --"
echo "--------------------------------------"

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
    mkfs.btrfs -f "${ROOT}"

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
mkfs.fat -F 32 "${EFI}"
mkdir -p /mnt/boot/efi
mount "${EFI}" /mnt/boot/efi

echo "--------------------------------------"
echo "--         fatest mirror            --"
echo "--------------------------------------"

reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist

echo "--------------------------------------"
echo "--    INSTALLING Base Arch Linux    --"
echo "--------------------------------------"
pacstrap /mnt base base-devel linux linux-firmware linux-headers iwd dhcpcd nano grub ntfs-3g os-prober efibootmgr bluez bluez-utils git --noconfirm --needed

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "---------------------------------------------"
echo "-- enable multilib and enable wifi and eth --"
echo "---------------------------------------------"

cat << 'REALEND' > /mnt/next.sh
#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Enable multilib repository
echo -e "\nEnabling multilib repository...\n"
{
    echo
    echo "[multilib]"
    echo "Include = /etc/pacman.d/mirrorlist"
} | tee -a /etc/pacman.conf > /dev/null

REALEND
# Update package database
pacman -Sy

# Enable necessary services
systemctl enable iwd dhcpcd

echo "---------------------------------------------"
echo "-- adding user and give it sudo permission --"
echo "---------------------------------------------"

# User creation and system configuration
useradd -m -b /home -G wheel,storage,power,audio,video "$USER"
usermod -c "$NAME" "$USER"
echo "$USER:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "-------------------------------------------------"
echo "        Setup Language to US and set locale      "
echo "-------------------------------------------------"

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

echo "--------------------------------------"
echo "--       Bootloader Installation    --"
echo "--------------------------------------"

# Bootloader installation
mkdir -p /boot/efi

# Ensure /boot/efi is mounted before running grub-install
if mount | grep -q '/boot/efi'; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || { echo "GRUB installation failed"; exit 1; }
    grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB configuration failed"; exit 1; }
else
    echo "/boot/efi is not mounted. Please mount it first."
    exit 1
fi


echo "-------------------------------------------------"
echo "                 Video Drivers                   "
echo "-------------------------------------------------"

# Video driver selection
echo "Select video driver:"
echo "1. AMD"
echo "2. Intel"
echo "3. NVIDIA"
read -p "Enter your choice (1, 2, or 3): " VIDEO_CHOICE

case "$VIDEO_CHOICE" in
    1) pacman -S vulkan-amdgpu mesa xf86-video-amdgpu --noconfirm --needed ;;
    2) pacman -S xorg mesa xf86-video-intel --noconfirm --needed ;;
    3) pacman -S xorg mesa nvidia nvidia-utils nvidia-settings opencl-nvidia nvidia-prime --noconfirm --needed ;;
    *) echo "Invalid video driver choice." ; exit 1 ;;
esac

echo "-------------------------------------------------"
echo "                 Audio Drivers                   "
echo "-------------------------------------------------"

# Audio driver selection
echo "Select audio driver:"
echo "1. PipeWire"
echo "2. PulseAudio"
read -p "Enter your choice (1 or 2): " AUDIO_CHOICE

case "$AUDIO_CHOICE" in
    1) pacman -S pipewire pipewire-alsa pipewire-pulse --noconfirm --needed
       systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service
       systemctl --user enable pipewire.service ;;
    2) pacman -S pulseaudio pulseaudio-alsa --noconfirm --needed
       systemctl enable pulseaudio ;;
    *) echo "Invalid audio driver choice." ; exit 1 ;;
esac

echo "-------------------------------------------------"
echo "              Desktop Environment                "
echo "-------------------------------------------------"

# Choose Desktop Environment
echo "Select Desktop Environment:"
echo "1. GNOME"
echo "2. Hyprland"
echo "3. XFCE"
echo "4. BSPWM"
echo "5. i3"
echo "6. KDE Plasma"
echo "7. Cinnamon"
read -p "Enter your choice (1-7): " DE_CHOICE

case "$DE_CHOICE" in
    1) pacman -S gnome-shell gnome-control-center gnome-calculator gnome-menus colord-gtk nautilus python-nautilus ffmpegthumbnailer gvfs-mtp file-roller xdg-desktop-portal-gnome gnome-tweaks gnome-terminal gnome-themes-extra gnome-color-manager gnome-backgrounds gnome-disk-utility gnome-screenshot gnome-shell-extensions evince loupe gnome-text-editor xdg-user-dirs-gtk --noconfirm --needed
       pacman -S ttf-liberation ttf-fira-sans ttf-jetbrains-mono noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra --noconfirm --needed ;;
    2) pacman -S hyprland xdg-desktop-portal-hyprland dunst kitty dolphin wofi qt5-wayland qt6-wayland polkit-kde-agent grim --noconfirm --needed ;;
    3) pacman -S xfce4 xfce4-goodies --noconfirm --needed ;;
    4) pacman -S bspwm sxhkd polybar dmenu rofi nitrogen picom --noconfirm --needed ;;
    5) pacman -S i3 i3status i3lock --noconfirm --needed ;;
    6) pacman -S plasma kde-applications --noconfirm --needed ;;
    7) pacman -S cinnamon --noconfirm --needed ;;
    *) echo "Invalid desktop environment choice." ; exit 1 ;;
esac

echo "-------------------------------------------------"
echo "                 Display Manager                 "
echo "-------------------------------------------------"

# Display Manager Selection
echo "Select Display Manager:"
echo "1. GDM"
echo "2. LY"
echo "3. SDDM"
echo "4. LightDM"
echo "5. LightDM with Slick Greeter"
read -p "Enter your choice (1-5): " DM_CHOICE

case "$DM_CHOICE" in
    1) pacman -S gdm --noconfirm --needed
       systemctl enable gdm ;;
    2) pacman -S ly --noconfirm --needed
       systemctl enable ly ;;
    3) pacman -S sddm qt6-svg --noconfirm --needed
       systemctl enable sddm ;;
    4) pacman -S lightdm lightdm-gtk-greeter --noconfirm --needed
       systemctl enable lightdm ;;
    5) pacman -S lightdm lightdm-slick-greeter --noconfirm --needed
       systemctl enable lightdm ;;
    *) echo "Invalid display manager choice. No display manager will be enabled." ;;
esac

echo "-------------------------------------------------"
echo "       Additional software installation          "
echo "-------------------------------------------------"

# Additional software installation
echo "Would you like to install some extra packages? (y/n)"
read -p "Enter your choice: " EXTRA_PACKAGES_CHOICE

if [[ "$EXTRA_PACKAGES_CHOICE" == "y" ]]; then
    read -p "Please enter the packages you want to install (space-separated): " EXTRA_PACKAGES
    pacman -S $EXTRA_PACKAGES --noconfirm --needed
else
    echo "Skipping extra package installation."
fi

echo "-------------------------------------------------"
echo "                 Mount drive                     "
echo "-------------------------------------------------"

# List available disks
echo "Available disks:"
lsblk

# Ask user if they want to mount any additional disks
read -p "Do you want to mount any disk for data or games? (y/n): " MOUNT_DISK_CHOICE

if [[ "$MOUNT_DISK_CHOICE" == "y" ]]; then
    # Show UUIDs of available disks
    echo "Available disk UUIDs:"
    blkid

    # Ask user for the UUID and label name
    read -p "Please enter the UUID of the disk you want to mount: " DISK_UUID
    read -p "Enter the desired mount point label name (e.g., data or games): " LABEL_NAME

    # Create the mount directory
    mkdir -p "/mnt/$LABEL_NAME"

    # Add to /etc/fstab
    echo "UUID=$DISK_UUID /mnt/$LABEL_NAME ext4 defaults,nosuid,nodev,nofail,x-gvfs-show,x-gvfs-name=$LABEL_NAME 0 0" >> /etc/fstab

    echo "Disk mounted successfully! Remember to mount it with 'mount -a' or reboot."
else
    echo "Skipping disk mounting."
fi

echo "-------------------------------------------------"
echo "              Clean up and unmount               "
echo "-------------------------------------------------"

# Clean up and unmount
echo "Unmounting partitions..."
umount -R /mnt

echo "-------------------------------------------------"
echo "      Install Complete, You can reboot now       "
echo "-------------------------------------------------"

# Execute the next steps in the new environment
arch-chroot /mnt sh /next.sh
