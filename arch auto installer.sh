#!/usr/bin/env bash

# Set up log file
LOG_FILE="/var/log/arch_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Disk Type Selection
echo "Please select your disk type:"
echo "1) SATA (e.g., /dev/sda)"
echo "2) NVMe (e.g., /dev/nvme0n1)"
read -p "Enter the number of your choice: " DISK_TYPE

if [[ "$DISK_TYPE" -eq 1 ]]; then
    echo "Please enter your SATA disk partition for EFI (e.g., /dev/sda1):"
    read EFI
    echo "Please enter your SATA disk partition for Root (e.g., /dev/sda3):"
    read ROOT
elif [[ "$DISK_TYPE" -eq 2 ]]; then
    echo "Please specify the NVMe device number (e.g., enter '0' for /dev/nvme0):"
    read NVME_NUM
    echo "Please specify the partition number for EFI (e.g., '1' for /dev/nvme0n1p1):"
    read EFI_PART_NUM
    echo "Please specify the partition number for Root (e.g., '2' for /dev/nvme0n1p2):"
    read ROOT_PART_NUM
    EFI="/dev/nvme${NVME_NUM}n1p${EFI_PART_NUM}"
    ROOT="/dev/nvme${NVME_NUM}n1p${ROOT_PART_NUM}"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# File System Selection
echo "Please select the filesystem type for the root partition:"
echo "1) Btrfs"
echo "2) ext4"
read -p "Enter the number of your choice: " FS_TYPE

# Continue with User Inputs
echo "Please enter your Username:"
read USER
echo "Please enter your Full Name:"
read NAME
echo "Please enter your Password:"
read -s PASSWORD

# Format partitions based on selected filesystem
if [[ "$FS_TYPE" -eq 1 ]]; then
    echo -e "\nCreating Btrfs Filesystem on ROOT...\n"
    mkfs.btrfs -f "${ROOT}"
    mkfs.vfat "${EFI}"
    
    # Mount target with subvolumes
    mount "${ROOT}" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    # Remount with Btrfs subvolumes
    mount -o compress=zstd,subvol=@ "${ROOT}" /mnt
    mkdir -p /mnt/{home,var,tmp,.snapshots,boot}
    mount -o compress=zstd,subvol=@home "${ROOT}" /mnt/home
    mount -o compress=zstd,subvol=@var "${ROOT}" /mnt/var
    mount -o compress=zstd,subvol=@tmp "${ROOT}" /mnt/tmp
    mount -o compress=zstd,subvol=@snapshots "${ROOT}" /mnt/.snapshots
elif [[ "$FS_TYPE" -eq 2 ]]; then
    echo -e "\nCreating ext4 Filesystem on ROOT...\n"
    mkfs.ext4 "${ROOT}"
    mkfs.vfat "${EFI}"

    # Mount partitions
    mount "${ROOT}" /mnt
    mkdir -p /mnt/boot
else
    echo "Invalid filesystem choice. Exiting."
    exit 1
fi

# Mount EFI partition
mount "$EFI" /mnt/boot

echo "--------------------------------------"
echo "-- INSTALLING Base Arch Linux --"
echo "--------------------------------------"
pacstrap /mnt base base-devel linux linux-firmware linux-headers git nano efibootmgr

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

echo "-------------------------------------------------"
echo "             Network Manager Setup               "
echo "-------------------------------------------------"

# Network Manager Setup
echo "Select a network manager to install:"
echo "1) wpa_supplicant"
echo "2) iwd"
read -p "Enter the number of your choice: " NETWORK_MANAGER_CHOICE

echo "-------------------------------------------------"
echo "             Bluetooth Activation                "
echo "-------------------------------------------------"

# Bluetooth Activation
echo "Do you want to activate Bluetooth?"
echo "1) Yes"
echo "2) No"
read -p "Enter your choice: " BLUETOOTH_CHOICE

echo "-------------------------------------------------"
echo "             Desktop Environment                 "
echo "-------------------------------------------------"

# Desktop Environment Selection
echo "Select a desktop environment or window manager to install:"
echo "1) GNOME"
echo "2) Hyprland"
echo "3) XFCE"
echo "4) No Desktop Environment (for a minimal setup)"
echo "5) BSPWM"
echo "6) KDE Plasma"
echo "7) Cinnamon"
echo "8) i3"
read -p "Enter the number of your choice: " DE_CHOICE

echo "-------------------------------------------------"
echo "                   Bootloader                    "
echo "-------------------------------------------------"


# Bootloader Selection
echo "Select a bootloader to install:"
echo "1) GRUB"
echo "2) Systemd-boot"
echo "3) rEFInd"
echo "4) Limine"
echo "5) Syslinux"
echo "6) Unified Kernel Image"
echo "7) EFI Boot Stub"
echo "8) GRUB Legacy"
echo "9) LILO"
read -p "Enter the number of your choice: " BOOTLOADER_CHOICE

echo "-------------------------------------------------"
echo "                 Audio System                    "
echo "-------------------------------------------------"

# Audio System Selection
echo "Select an audio system to install:"
echo "1) PipeWire"
echo "2) PulseAudio"
read -p "Enter the number of your choice: " AUDIO_CHOICE

echo "-------------------------------------------------"
echo "                     CPU                         "
echo "-------------------------------------------------"

# CPU Type Selection
echo "What type of CPU do you have?"
echo "1) AMD"
echo "2) Intel"
read -p "Enter the number of your choice: " CPU_CHOICE

echo "-------------------------------------------------"
echo "                   GPU Driver                    "
echo "-------------------------------------------------"

# GPU Driver Selection
echo "Select a GPU driver to install:"
echo "1) AMD"
echo "2) Intel"
echo "3) NVIDIA"
read -p "Enter the number of your choice: " GPU_CHOICE

echo "-------------------------------------------------"
echo "                Display Manager                  "
echo "-------------------------------------------------"


# Display Manager Selection
echo "Select a display manager to install:"
echo "1) SDDM"
echo "2) GDM"
echo "3) LY"
echo "4) LightDM"
echo "5) LightDM with Slick Greeter"
read -p "Enter the number of your choice: " DM_CHOICE

# Create post-install script
cat <<REALEND > /mnt/next.sh
#!/bin/bash

# User Setup
useradd -m $USER
usermod -c "${NAME}" $USER
usermod -aG wheel,storage,power,audio,video $USER
echo "$USER:$PASSWORD" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Locale and Time Settings
echo "Setting up Locale and Timezone..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

# Hostname Configuration
echo "archlinux" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1	localhost
::1			localhost
127.0.1.1	archlinux.localdomain	archlinux
EOF

# Bootloader Installation
echo "Installing Selected Bootloader..."

case $BOOTLOADER_CHOICE in
  1)
    # GRUB
    pacman -S grub grub-btrfs --noconfirm --needed
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Arch Linux"
    grub-mkconfig -o /boot/grub/grub.cfg
    ;;
  2)
    # Systemd-boot
    bootctl --path=/boot install || { echo "Failed to install systemd-boot"; exit 1; }
    mkdir -p /boot/loader/entries
    # Create loader configuration
    cat <<EOF > /boot/loader/loader.conf
timeout 3
console-mode max
default arch
editor no
EOF
    # Create boot entry for Arch Linux
    cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=${ROOT} rw
EOF
    ;;
  3)
    # rEFInd
    pacman -S refind --noconfirm --needed
    refind-install
    ;;
  4)
    # Limine (Experimental)
    echo "Limine installation requires additional steps. Consult Limine documentation."
    ;;
  5)
    # Syslinux
    pacman -S syslinux --noconfirm --needed
    syslinux-install_update -i -a -m
    ;;
  6)
    # Unified Kernel Image (Experimental)
    echo "Unified Kernel Image setup requires additional steps."
    ;;
  7)
    # EFI Boot Stub
    echo "EFI Boot Stub setup requires additional steps."
    ;;
  8)
    # GRUB Legacy (Deprecated)
    echo "Installing GRUB Legacy is not recommended. GRUB2 will be used."
    pacman -S grub --noconfirm --needed
    grub-install --target=i386-pc /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg
    ;;
  9)
    # LILO
    pacman -S lilo --noconfirm --needed
    lilo
    ;;
  *)
    echo "Invalid choice. Defaulting to GRUB."
    pacman -S grub --noconfirm --needed
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Arch Linux"
    grub-mkconfig -o /boot/grub/grub.cfg
    ;;
esac

# Audio System Installation
echo "Installing Selected Audio System..."
if [ "$AUDIO_CHOICE" -eq 1 ]; then
  pacman -S pipewire pipewire-alsa pipewire-pulse pavucontrol --noconfirm --needed
  systemctl --user enable pipewire pipewire-pulse
elif [ "$AUDIO_CHOICE" -eq 2 ]; then
  pacman -S pulseaudio pulseaudio-alsa pavucontrol --noconfirm --needed
  systemctl --user enable pulseaudio
else
  echo "Invalid audio choice. Defaulting to PipeWire."
  pacman -S pipewire pipewire-alsa pipewire-pulse --noconfirm --needed
  systemctl --user enable pipewire pipewire-pulse
fi

# Install Microcode
if [ "$CPU_CHOICE" -eq 1 ]; then
    echo "Installing AMD microcode..."
    pacman -S amd-ucode --noconfirm --needed
elif [ "$CPU_CHOICE" -eq 2 ]; then
    echo "Installing Intel microcode..."
    pacman -S intel-ucode --noconfirm --needed
else
    echo "Invalid choice. No microcode will be installed."
fi

# GPU Driver Installation
echo "Installing Selected GPU Driver..."
if [ "$GPU_CHOICE" -eq 1 ]; then
  pacman -S xf86-video-amdgpu mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver libva-utils --noconfirm --needed
elif [ "$GPU_CHOICE" -eq 2 ]; then
  pacman -S xf86-video-intel --noconfirm --needed
elif [ "$GPU_CHOICE" -eq 3 ]; then
  pacman -S nvidia nvidia-utils --noconfirm --needed
else
  echo "Invalid GPU choice. No driver will be installed."
fi

# Display Manager Installation
echo "Installing Selected Display Manager..."
case $DM_CHOICE in
  1)
    pacman -S sddm --noconfirm --needed
    systemctl enable sddm
    ;;
  2)
    pacman -S gdm --noconfirm --needed
    systemctl enable gdm
    ;;
  3)
    pacman -S ly --noconfirm --needed
    systemctl enable ly
    ;;
  4)
    pacman -S lightdm lightdm-gtk-greeter --noconfirm --needed
    systemctl enable lightdm
    ;;
  5)
    pacman -S lightdm lightdm-slick-greeter --noconfirm --needed
    systemctl enable lightdm
    ;;
  *)
    echo "Invalid choice. Defaulting to SDDM."
    pacman -S sddm --noconfirm --needed
    systemctl enable sddm
    ;;
esac

case $NETWORK_MANAGER_CHOICE in
  1)
    pacman -S networkmanager wpa_supplicant wireless_tools --noconfirm --needed
    systemctl enable wpa_supplicant NetworkManager
    echo "wpa_supplicant has been installed and enabled."
    ;;
  2)
    pacman -S iwd dhcpcd --noconfirm --needed
    systemctl enable iwd dhcpcd
    echo "iwd has been installed and enabled."
    ;;
  *)
    echo "Invalid choice. No network manager will be installed."
    ;;
esac

case $BLUETOOTH_CHOICE in
  1)
    pacman -S bluez bluez-utils --noconfirm --needed
    systemctl enable bluetooth
    echo "Bluetooth has been activated."
    ;;
  2)
    echo "Bluetooth will not be activated."
    ;;
  *)
    echo "Invalid choice. Bluetooth will not be activated."
    ;;
esac

# Install Selected Desktop Environment or Window Manager
echo "Installing Selected Desktop Environment or Window Manager..."

case $DE_CHOICE in
  1)
    pacman -S gnome-shell gnome-control-center gnome-menus nautilus python-nautilus ffmpegthumbnailer gvfs-mtp file-roller xdg-desktop-portal-gnome gnome-tweaks gnome-terminal gnome-themes-extra gnome-color-manager gnome-backgrounds gnome-disk-utility gnome-shell-extensions gnome-text-editor xdg-user-dirs-gtk --noconfirm --needed
    ;;
  2)
    pacman -S hyprland kitty --noconfirm --needed
    ;;
  3)
    pacman -S xfce4 xfce4-goodies --noconfirm --needed
    ;;
  4)
    echo "No Desktop Environment selected. Proceeding with minimal setup..."
    # You can add any additional setup here for a minimal install if needed
    ;;
  5)
    pacman -S bspwm sxhkd --noconfirm --needed
    ;;
  6)
    pacman -S plasma kde-applications --noconfirm --needed
    ;;
  7)
    pacman -S cinnamon --noconfirm --needed
    ;;
  8)
    pacman -S i3 i3status dmenu --noconfirm --needed
    ;;
  *)
    echo "Invalid choice. No Desktop Environment or Window Manager will be installed."
    ;;
esac

# Final messages
echo "-------------------------------------------------"
echo "Installation Complete! You can reboot now."
echo "-------------------------------------------------"

REALEND

# Run the next.sh script in the chroot environment
arch-chroot /mnt sh /next.sh
