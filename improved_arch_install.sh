#!/usr/bin/env bash

echo "Select disk type:"
echo "1. NVMe"
echo "2. SATA/Other"
read DISK_TYPE

if [[ "$DISK_TYPE" -eq 1 ]]; then
    echo "Please specify the NVMe device number (e.g., '0' for /dev/nvme0n1):"
    read NVME_NUM
    echo "Please specify the partition number for EFI (e.g., '1' for /dev/nvme0n1p1):"
    read EFI_PART_NUM
    echo "Please specify the partition number for Root (e.g., '2' for /dev/nvme0n1p2):"
    read ROOT_PART_NUM
    EFI="/dev/nvme${NVME_NUM}n1p${EFI_PART_NUM}"
    ROOT="/dev/nvme${NVME_NUM}n1p${ROOT_PART_NUM}"
    DISK="/dev/nvme${NVME_NUM}n1"
elif [[ "$DISK_TYPE" -eq 2 ]]; then
    echo "Please enter EFI partition: (example /dev/sda1)"
    read EFI
    echo "Please enter Root( / ) partition: (example /dev/sda2)"
    read ROOT
    echo "Please enter disk device: (example /dev/sda)"
    read DISK
else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo "Please enter your username"
read USER
echo "Please enter your password"
read PASSWORD
echo "Please choose Your Desktop Environment"
echo "1. GNOME"
echo "2. KDE"
echo "3. XFCE"
echo "4. Hyprland"
read DESKTOP

echo "Please choose Your Bootloader"
echo "1. systemd-boot"
echo "2. EFISTUB with efibootmgr"
read BOOTLOADER

echo "-------------------------------------------------"
echo "                Display Manager                  "
echo "-------------------------------------------------"
echo "Select a display manager to install:"
echo "1) SDDM"
echo "2) GDM"
echo "3) LY"
echo "4) LightDM"
echo "5) LightDM with Slick Greeter"
read -p "Enter the number of your choice: " DM_CHOICE

echo ""
echo "WARNING: This will erase all data on the following partitions:"
echo "  EFI:  ${EFI}"
echo "  ROOT: ${ROOT}"
echo ""
read -p "Continue? (y/N): " confirm
[[ $confirm == [yY] ]] || exit 1

echo "Please enter LUKS encryption password for Root"
read -s LUKS_PASSWORD_ROOT
echo ""

echo "------------------------------------------"
echo "-- Encrypting Root Partition with LUKS2 --"
echo "------------------------------------------"
echo -n "${LUKS_PASSWORD_ROOT}" | cryptsetup luksFormat --type luks2 "${ROOT}" -
echo -n "${LUKS_PASSWORD_ROOT}" | cryptsetup open "${ROOT}" cryptroot -
unset LUKS_PASSWORD_ROOT

# make filesystems
echo -e "\nCreating Filesystems...\n"
mkfs.vfat -F32 -n "BOOT" -f "${EFI}"
mkfs.btrfs -f -L "Arch Linux" /dev/mapper/cryptroot

# mount target and create subvolumes for root
mount -t btrfs /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
umount /mnt

# mount root subvolumes
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var,tmp,.snapshots}
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

mkdir /mnt/boot
mount -t vfat "${EFI}" /mnt/boot/

echo "------------------------------------------"
echo "-- INSTALLING Arch Linux BASE on Main Drive --"
echo "------------------------------------------"
pacstrap /mnt base base-devel --noconfirm --needed
# kernel
pacstrap /mnt linux linux-firmware --noconfirm --needed
echo "------------------------------------------"
echo "-- Setup Dependencies --"
echo "------------------------------------------"
pacstrap /mnt networkmanager network-manager-applet wireless_tools nano intel-ucode bluez bluez-utils blueman git btrfs-progs zram-generator efibootmgr --noconfirm --needed

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Get UUID of encrypted partition
ROOT_UUID=$(blkid -s UUID -o value "${ROOT}")
EFI_PART_NUM=$(echo "${EFI}" | grep -oP '\d+$')

echo "------------------------------------------"
echo "-- Bootloader Installation --"
echo "------------------------------------------"

if [[ "$BOOTLOADER" -eq 1 ]]; then
    echo "Installing systemd-boot..."
    bootctl install --path /mnt/boot
    echo "default arch.conf" > /mnt/boot/loader/loader.conf
    
    cat <<EOF > /mnt/boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options rd.luks.name=${ROOT_UUID}=cryptroot rd.luks.options=${ROOT_UUID}=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOF

elif [[ "$BOOTLOADER" -eq 2 ]]; then
    echo "Setting up EFISTUB with efibootmgr..."
    BOOTLOADER_SETUP="efibootmgr --disk ${DISK} --part ${EFI_PART_NUM} --create --label \"Arch Linux\" --loader /vmlinuz-linux --unicode 'rd.luks.name=${ROOT_UUID}=cryptroot rd.luks.options=${ROOT_UUID}=discard root=/dev/mapper/cryptroot rootflags=subvol=@ rw initrd=\intel-ucode.img initrd=\initramfs-linux.img' --verbose"
else
    echo "Invalid bootloader choice. Exiting."
    exit 1
fi

cat <<REALEND > /mnt/next.sh
useradd -m $USER
usermod -G wheel,storage,power,audio $USER
echo $USER:$PASSWORD | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "------------------------------------------"
echo "Setup Language to US and set locale"
echo "------------------------------------------"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Kathmandu /etc/localtime
hwclock --systohc

cat <<EOF > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 arch.localdomain arch
EOF

echo "----------------------------------------"
echo "Configure mkinitcpio for encryption"
echo "----------------------------------------"
sed -i 's/^MODULES=.*/MODULES=(btrfs usbhid atkbd)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap consolefont sd-encrypt block filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

echo "----------------------------------------"
echo "Setup EFISTUB bootloader"
echo "----------------------------------------"
if [[ $BOOTLOADER -eq 2 ]]; then
    $BOOTLOADER_SETUP
fi

echo "----------------------------------------"
echo "Setup zram"
echo "----------------------------------------"
cat <<ZRAM > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
ZRAM

echo "----------------------------------------"
echo "Display and Audio Drivers"
echo "----------------------------------------"
pacman -S xorg pulseaudio --noconfirm --needed

systemctl enable NetworkManager bluetooth

# DESKTOP ENVIRONMENT
if [[ $DESKTOP == '1' ]]
then
    echo "Installing GNOME..."
    pacman -S gnome --noconfirm --needed
elif [[ $DESKTOP == '2' ]]
then
    echo "Installing KDE Plasma..."
    pacman -S plasma kde-applications --noconfirm --needed
elif [[ $DESKTOP == '3' ]]
then
    echo "Installing XFCE..."
    pacman -S xfce4 xfce4-goodies --noconfirm --needed
elif [[ $DESKTOP == '4' ]]
then
    echo "Installing Hyprland..."
    pacman -S hyprland dunst kitty uwsm dolphin wofi xdg-desktop-portal-hyprland qt5-wayland qt6-wayland polkit-kde-agent grim slurp --noconfirm --needed
else
    echo "No desktop environment selected"
fi

echo "-------------------------------------------------"
echo "           Display Manager Installation          "
echo "-------------------------------------------------"
# Install and enable selected display manager
case $DM_CHOICE in
    1)
        echo "Installing SDDM..."
        pacman -S sddm --noconfirm --needed
        systemctl enable sddm
        ;;
    2)
        echo "Installing GDM..."
        pacman -S gdm --noconfirm --needed
        systemctl enable gdm
        ;;
    3)
        echo "Installing LY..."
        pacman -S ly --noconfirm --needed
        systemctl enable ly
        ;;
    4)
        echo "Installing LightDM..."
        pacman -S lightdm lightdm-gtk-greeter --noconfirm --needed
        systemctl enable lightdm
        ;;
    5)
        echo "Installing LightDM with Slick Greeter..."
        pacman -S lightdm lightdm-slick-greeter --noconfirm --needed
        sed -i 's/^#greeter-session=.*/greeter-session=lightdm-slick-greeter/' /etc/lightdm/lightdm.conf
        systemctl enable lightdm
        ;;
    *)
        echo "Invalid choice. No display manager installed."
        ;;
esac

echo "----------------------------------------"
echo "Install Complete, You can reboot now"
echo "----------------------------------------"
REALEND

arch-chroot /mnt sh next.sh
