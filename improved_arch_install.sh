#!/usr/bin/env bash

# Enhanced error handling
set -euo pipefail

# Global variables
LOG_FILE="/var/log/arch_install.log"
SCRIPT_VERSION="2025.1"
START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error handling function
error_handler() {
    local line_number="${1}"
    echo -e "${RED}[ERROR]${NC} Script failed at line: ${line_number}"
    echo -e "${YELLOW}[CLEANUP]${NC} Attempting to clean up..."
    
    # Cleanup mounted filesystems
    umount -R /mnt 2>/dev/null || true
    
    # Close any open encrypted volumes
    cryptsetup close cryptroot 2>/dev/null || true
    
    echo -e "${RED}[ABORT]${NC} Installation aborted due to error."
    exit 1
}

# Success handler
success_handler() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    echo -e "${GREEN}[SUCCESS]${NC} Installation completed successfully in ${duration} seconds!"
}

# Set up error trapping
trap 'error_handler ${LINENO}' ERR
trap success_handler EXIT

# Logging setup
setup_logging() {
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo -e "${BLUE}[INFO]${NC} Arch Linux Installation Script v${SCRIPT_VERSION}"
    echo -e "${BLUE}[INFO]${NC} Started at: $(date)"
    echo -e "${BLUE}[INFO]${NC} Logging to: ${LOG_FILE}"
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    local percent=$((current * 100 / total))
    echo -e "${BLUE}[${current}/${total}]${NC} (${percent}%) ${message}"
}

# Input validation functions
validate_partition() {
    local partition="$1"
    if ! lsblk "$partition" &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Partition $partition does not exist"
        return 1
    fi
    return 0
}

validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z][-a-z0-9]*$ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid username. Use lowercase letters, numbers, and hyphens only."
        return 1
    fi
    return 0
}

validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]*[a-zA-Z0-9]$ ]]; then
        echo -e "${RED}[ERROR]${NC} Invalid hostname format."
        return 1
    fi
    return 0
}

# Network connectivity check
check_internet() {
    echo -e "${YELLOW}[CHECK]${NC} Verifying internet connectivity..."
    if ! ping -c 3 archlinux.org &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} No internet connectivity. Please configure network first."
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} Internet connectivity confirmed."
}

# Secure password input
get_secure_password() {
    local prompt="$1"
    local password=""
    local confirm=""
    
    while true; do
        echo -n "$prompt: "
        read -s password
        echo
        echo -n "Confirm password: "
        read -s confirm
        echo
        
        if [[ "$password" == "$confirm" ]]; then
            if [[ ${#password} -lt 8 ]]; then
                echo -e "${RED}[ERROR]${NC} Password must be at least 8 characters long."
                continue
            fi
            echo "$password"
            return 0
        else
            echo -e "${RED}[ERROR]${NC} Passwords do not match. Please try again."
        fi
    done
}

# System requirements check
check_system_requirements() {
    echo -e "${YELLOW}[CHECK]${NC} Verifying system requirements..."
    
    # Check if running in UEFI mode
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        echo -e "${RED}[ERROR]${NC} This script requires UEFI boot mode."
        exit 1
    fi
    
    # Check available memory
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    if [[ $mem_mb -lt 512 ]]; then
        echo -e "${RED}[ERROR]${NC} Insufficient memory. At least 512MB required."
        exit 1
    fi
    
    echo -e "${GREEN}[OK]${NC} System requirements met."
}
# Disk selection with enhanced validation
select_disk_type() {
    echo -e "${BLUE}[INPUT]${NC} Disk Type Selection"
    echo "1) SATA (e.g., /dev/sda)"
    echo "2) NVMe (e.g., /dev/nvme0n1)"
    
    while true; do
        read -p "Enter the number of your choice: " DISK_TYPE
        case "$DISK_TYPE" in
            1|2) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1 or 2." ;;
        esac
    done
}

# Enhanced disk partition selection
select_partitions() {
    if [[ "$DISK_TYPE" -eq 1 ]]; then
        echo -e "${YELLOW}[INFO]${NC} Available SATA disks:"
        lsblk -d -o NAME,SIZE,MODEL | grep "sd"
        
        while true; do
            read -p "Enter your SATA disk partition for EFI (e.g., /dev/sda1): " EFI
            if validate_partition "$EFI"; then break; fi
        done
        
        while true; do
            read -p "Enter your SATA disk partition for Root (e.g., /dev/sda3): " ROOT
            if validate_partition "$ROOT"; then break; fi
        done
        
    elif [[ "$DISK_TYPE" -eq 2 ]]; then
        echo -e "${YELLOW}[INFO]${NC} Available NVMe disks:"
        lsblk -d -o NAME,SIZE,MODEL | grep "nvme"
        
        while true; do
            read -p "Enter NVMe device number (e.g., '0' for /dev/nvme0): " NVME_NUM
            read -p "Enter partition number for EFI (e.g., '1' for p1): " EFI_PART_NUM
            read -p "Enter partition number for Root (e.g., '2' for p2): " ROOT_PART_NUM
            
            EFI="/dev/nvme${NVME_NUM}n1p${EFI_PART_NUM}"
            ROOT="/dev/nvme${NVME_NUM}n1p${ROOT_PART_NUM}"
            
            if validate_partition "$EFI" && validate_partition "$ROOT"; then
                break
            fi
        done
    fi
    
    echo -e "${GREEN}[SELECTED]${NC} EFI: ${EFI}, Root: ${ROOT}"
}

# Disk encryption setup
setup_encryption() {
    echo -e "${BLUE}[INPUT]${NC} Disk Encryption Setup"
    echo "1) Enable LUKS encryption (Recommended for security)"
    echo "2) No encryption"
    
    while true; do
        read -p "Enter your choice: " ENCRYPTION_CHOICE
        case "$ENCRYPTION_CHOICE" in
            1) 
                ENCRYPTION_ENABLED=true
                echo -e "${YELLOW}[WARNING]${NC} You will need to enter a strong encryption passphrase."
                ENCRYPTION_PASSPHRASE=$(get_secure_password "Enter encryption passphrase")
                break
                ;;
            2) 
                ENCRYPTION_ENABLED=false
                echo -e "${YELLOW}[WARNING]${NC} Proceeding without disk encryption."
                break
                ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1 or 2." ;;
        esac
    done
}
# Enhanced filesystem selection
select_filesystem() {
    echo -e "${BLUE}[INPUT]${NC} Filesystem Selection"
    echo "1) Btrfs (Recommended - with snapshots and compression)"
    echo "2) ext4 (Traditional and stable)"
    
    while true; do
        read -p "Enter your choice: " FS_TYPE
        case "$FS_TYPE" in
            1|2) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1 or 2." ;;
        esac
    done
}

# Enhanced user configuration
configure_user() {
    echo -e "${BLUE}[INPUT]${NC} User Configuration"
    
    while true; do
        read -p "Enter your username: " USER
        if validate_username "$USER"; then break; fi
    done
    
    read -p "Enter your full name: " NAME
    
    USER_PASSWORD=$(get_secure_password "Enter user password")
    ROOT_PASSWORD=$(get_secure_password "Enter root password")
    
    echo -e "${GREEN}[OK]${NC} User configuration completed."
}

# System configuration
configure_system() {
    echo -e "${BLUE}[INPUT]${NC} System Configuration"
    
    while true; do
        read -p "Enter hostname for this system: " HOSTNAME
        if validate_hostname "$HOSTNAME"; then break; fi
    done
    
    echo -e "${YELLOW}[INFO]${NC} Available timezones (showing common ones):"
    echo "1) America/New_York"
    echo "2) Europe/London" 
    echo "3) Asia/Tokyo"
    echo "4) Australia/Sydney"
    echo "5) Custom (specify your own)"
    
    read -p "Select timezone (1-5): " TZ_CHOICE
    case "$TZ_CHOICE" in
        1) TIMEZONE="America/New_York" ;;
        2) TIMEZONE="Europe/London" ;;
        3) TIMEZONE="Asia/Tokyo" ;;
        4) TIMEZONE="Australia/Sydney" ;;
        5) 
            read -p "Enter custom timezone (e.g., Asia/Kathmandu): " TIMEZONE
            if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
                echo -e "${YELLOW}[WARNING]${NC} Timezone will be validated during installation."
            fi
            ;;
        *) TIMEZONE="UTC" ;;
    esac
    
    echo -e "${GREEN}[SELECTED]${NC} Hostname: ${HOSTNAME}, Timezone: ${TIMEZONE}"
}
# Network manager selection
select_network_manager() {
    echo -e "${BLUE}[INPUT]${NC} Network Manager Selection"
    echo "1) NetworkManager (Recommended for desktop)"
    echo "2) systemd-networkd + iwd (Minimal/server)"
    echo "3) wpa_supplicant (Legacy)"
    
    while true; do
        read -p "Enter your choice: " NETWORK_MANAGER_CHOICE
        case "$NETWORK_MANAGER_CHOICE" in
            1|2|3) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done
}

# Audio system selection
select_audio_system() {
    echo -e "${BLUE}[INPUT]${NC} Audio System Selection"
    echo "1) PipeWire (Modern, recommended)"
    echo "2) PulseAudio (Traditional)"
    
    while true; do
        read -p "Enter your choice: " AUDIO_CHOICE
        case "$AUDIO_CHOICE" in
            1|2) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1 or 2." ;;
        esac
    done
}

# Desktop environment selection with updated packages
select_desktop_environment() {
    echo -e "${BLUE}[INPUT]${NC} Desktop Environment Selection"
    echo "1) GNOME (Full featured)"
    echo "2) KDE Plasma (Customizable)"
    echo "3) XFCE (Lightweight)"
    echo "4) Hyprland (Wayland tiling)"
    echo "5) i3 (X11 tiling)"
    echo "6) Minimal (No DE)"
    
    while true; do
        read -p "Enter your choice: " DE_CHOICE
        case "$DE_CHOICE" in
            1|2|3|4|5|6) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1-6." ;;
        esac
    done
}
# CPU selection with enhanced detection
select_cpu_type() {
    echo -e "${BLUE}[INPUT]${NC} CPU Type Selection"
    
    # Auto-detect CPU if possible
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        AUTO_CPU="AMD"
    elif grep -q "GenuineIntel" /proc/cpuinfo; then
        AUTO_CPU="Intel"
    else
        AUTO_CPU="Unknown"
    fi
    
    echo "Auto-detected: ${AUTO_CPU}"
    echo "1) AMD"
    echo "2) Intel"
    echo "3) Use auto-detection"
    
    while true; do
        read -p "Enter your choice: " CPU_CHOICE
        case "$CPU_CHOICE" in
            1|2) break ;;
            3) 
                if [[ "$AUTO_CPU" == "AMD" ]]; then
                    CPU_CHOICE=1
                elif [[ "$AUTO_CPU" == "Intel" ]]; then
                    CPU_CHOICE=2
                else
                    echo -e "${RED}[ERROR]${NC} Cannot auto-detect CPU type."
                    continue
                fi
                break
                ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done
}

# GPU selection with enhanced options
select_gpu_driver() {
    echo -e "${BLUE}[INPUT]${NC} GPU Driver Selection"
    echo "1) AMD (RDNA/GCN)"
    echo "2) Intel (integrated)"
    echo "3) NVIDIA (proprietary)"
    echo "4) NVIDIA (open-source nouveau)"
    echo "5) Multiple GPUs"
    
    while true; do
        read -p "Enter your choice: " GPU_CHOICE
        case "$GPU_CHOICE" in
            1|2|3|4|5) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1-5." ;;
        esac
    done
}
# Bootloader selection with modern options
select_bootloader() {
    echo -e "${BLUE}[INPUT]${NC} Bootloader Selection"
    echo "1) systemd-boot (Recommended for UEFI)"
    echo "2) GRUB (Universal compatibility)"
    echo "3) rEFInd (Advanced users)"
    
    while true; do
        read -p "Enter your choice: " BOOTLOADER_CHOICE
        case "$BOOTLOADER_CHOICE" in
            1|2|3) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done
}

# Display manager selection
select_display_manager() {
    echo -e "${BLUE}[INPUT]${NC} Display Manager Selection"
    echo "1) SDDM (KDE/Qt based)"
    echo "2) GDM (GNOME/GTK based)"
    echo "3) LightDM (Lightweight)"
    echo "4) ly (Console based)"
    echo "5) None (startx/manual)"
    
    while true; do
        read -p "Enter your choice: " DM_CHOICE
        case "$DM_CHOICE" in
            1|2|3|4|5) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1-5." ;;
        esac
    done
}

# Security options
select_security_options() {
    echo -e "${BLUE}[INPUT]${NC} Security & Hardening Options"
    echo "Do you want to enable additional security features?"
    echo "1) Yes (UFW firewall, AppArmor, fail2ban)"
    echo "2) Basic (UFW firewall only)"
    echo "3) None"
    
    while true; do
        read -p "Enter your choice: " SECURITY_CHOICE
        case "$SECURITY_CHOICE" in
            1|2|3) break ;;
            *) echo -e "${RED}[ERROR]${NC} Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done
}
# Disk preparation with encryption support
prepare_disks() {
    show_progress 1 10 "Preparing disk partitions..."
    
    # Save original root partition before encryption
    ORIGINAL_ROOT="$ROOT"
    
    # Setup encryption if enabled
    if [[ "$ENCRYPTION_ENABLED" == true ]]; then
        echo -e "${YELLOW}[CRYPT]${NC} Setting up LUKS encryption..."
        echo -n "$ENCRYPTION_PASSPHRASE" | cryptsetup -y -v luksFormat "${ROOT}" -
        echo -n "$ENCRYPTION_PASSPHRASE" | cryptsetup open "${ROOT}" cryptroot -
        ROOT="/dev/mapper/cryptroot"
        echo -e "${GREEN}[OK]${NC} Encryption setup complete."
    fi
    
    # Format partitions based on filesystem choice
    if [[ "$FS_TYPE" -eq 1 ]]; then
        echo -e "${YELLOW}[FORMAT]${NC} Creating Btrfs filesystem..."
        mkfs.btrfs -f "${ROOT}"
        mkfs.vfat -F32 "${EFI}"
        
        # Create Btrfs subvolumes
        mount "${ROOT}" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        btrfs subvolume create /mnt/@var
        btrfs subvolume create /mnt/@tmp
        btrfs subvolume create /mnt/@snapshots
        btrfs subvolume create /mnt/@swap
        umount /mnt
        
        # Mount with optimized options
        mount -o compress=zstd:1,noatime,subvol=@ "${ROOT}" /mnt
        mkdir -p /mnt/{home,var,tmp,.snapshots,swap,boot}
        mount -o compress=zstd:1,noatime,subvol=@home "${ROOT}" /mnt/home
        mount -o compress=zstd:1,noatime,subvol=@var "${ROOT}" /mnt/var
        mount -o compress=zstd:1,noatime,subvol=@tmp "${ROOT}" /mnt/tmp
        mount -o compress=zstd:1,noatime,subvol=@snapshots "${ROOT}" /mnt/.snapshots
        mount -o noatime,subvol=@swap "${ROOT}" /mnt/swap
        
    else
        echo -e "${YELLOW}[FORMAT]${NC} Creating ext4 filesystem..."
        mkfs.ext4 -F "${ROOT}"
        mkfs.vfat -F32 "${EFI}"
        mount "${ROOT}" /mnt
        mkdir -p /mnt/boot
    fi
    
    # Mount EFI partition
    mount "${EFI}" /mnt/boot
    echo -e "${GREEN}[OK]${NC} Disk preparation complete."
}
# Install base system with modern packages
install_base_system() {
    show_progress 2 10 "Installing base system..."
    
    # Update mirrorlist for faster downloads
    echo -e "${YELLOW}[MIRROR]${NC} Optimizing package mirrors..."
    pacman -Sy --noconfirm reflector
    reflector --country "Netherlands" --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    # Base packages with modern additions
    local BASE_PACKAGES=(
        "base" 
        "base-devel" 
        "linux" 
        "linux-firmware" 
        "linux-headers" 
        "git" 
        "vim" 
        "efibootmgr" 
        "dhcpcd" 
        "reflector" 
        "pacman-contrib" 
        "archlinux-keyring" 
        "curl"
        "cryptsetup"
    )
    
    # Add CPU microcode
    if [[ "$CPU_CHOICE" -eq 1 ]]; then
        BASE_PACKAGES+=("amd-ucode")
    elif [[ "$CPU_CHOICE" -eq 2 ]]; then
        BASE_PACKAGES+=("intel-ucode")
    fi
    
    # Add filesystem tools
    if [[ "$FS_TYPE" -eq 1 ]]; then
        BASE_PACKAGES+=("btrfs-progs" "snapper")
    else
        BASE_PACKAGES+=("e2fsprogs")
    fi
    
    # Install base system
    pacstrap /mnt "${BASE_PACKAGES[@]}"
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    echo -e "${GREEN}[OK]${NC} Base system installation complete."
}
# Create enhanced post-install script
create_post_install_script() {
    show_progress 3 10 "Creating post-installation script..."
    
    cat <<'POSTINSTALL_EOF' > /mnt/next.sh
#!/bin/bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[POST]${NC} Starting post-installation configuration..."

# Configure encryption support in initramfs if needed
if [[ "${ENCRYPTION_ENABLED}" == "true" ]]; then
    echo -e "${YELLOW}[CRYPT]${NC} Configuring initramfs for encryption..."
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P
fi

# System configuration
echo -e "${YELLOW}[CONFIG]${NC} Configuring system settings..."

# Locale and time settings
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Hostname configuration
echo "${HOSTNAME}" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.1.1	${HOSTNAME}.localdomain	${HOSTNAME}
EOF

# User creation and configuration
echo -e "${YELLOW}[USER]${NC} Setting up user accounts..."
useradd -m -G wheel,storage,power,audio,video,optical,lp,scanner "${USER}"
usermod -c "${NAME}" "${USER}"

# Set passwords
echo "${USER}:${USER_PASSWORD}" | chpasswd
echo "root:${ROOT_PASSWORD}" | chpasswd

# Configure sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
echo 'Defaults timestamp_timeout=15' >> /etc/sudoers
POSTINSTALL_EOF

    # Pass variables to the script
    sed -i "s/\${TIMEZONE}/$TIMEZONE/g" /mnt/next.sh
    sed -i "s/\${HOSTNAME}/$HOSTNAME/g" /mnt/next.sh
    sed -i "s/\${USER}/$USER/g" /mnt/next.sh
    sed -i "s/\${NAME}/$NAME/g" /mnt/next.sh
    sed -i "s/\${USER_PASSWORD}/$USER_PASSWORD/g" /mnt/next.sh
    sed -i "s/\${ROOT_PASSWORD}/$ROOT_PASSWORD/g" /mnt/next.sh
    sed -i "s/\${ENCRYPTION_ENABLED}/$ENCRYPTION_ENABLED/g" /mnt/next.sh
}
# Continue the post-install script with bootloader configuration
add_bootloader_config() {
    cat <<'BOOTLOADER_EOF' >> /mnt/next.sh

# Bootloader installation
echo -e "${YELLOW}[BOOT]${NC} Installing bootloader..."
case ${BOOTLOADER_CHOICE} in
    1)
        # systemd-boot (recommended)
        echo -e "${BLUE}[INFO]${NC} Installing systemd-boot..."
        bootctl --esp-path=/boot install
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}[ERROR]${NC} Failed to install systemd-boot"
            exit 1
        fi
        
        mkdir -p /boot/loader/entries
        
        # Create loader configuration
        cat <<EOF > /boot/loader/loader.conf
timeout 3
console-mode max
default arch.conf
editor no
EOF
        
        # Determine root device and parameters
        if [[ "${ENCRYPTION_ENABLED}" == "true" ]]; then
            ROOT_DEVICE="${ORIGINAL_ROOT}"
            KERNEL_PARAMS="cryptdevice=${ORIGINAL_ROOT}:cryptroot root=/dev/mapper/cryptroot rw"
        else
            ROOT_DEVICE="${ROOT_DEVICE_FOR_BOOT}"
            KERNEL_PARAMS="rw"
        fi
        
        # Get UUID of the actual root filesystem
        ROOT_UUID=$(blkid -s UUID -o value ${ROOT_DEVICE_FOR_BOOT})
        
        # Create main boot entry
        cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd ${MICROCODE_INITRD}
initrd /initramfs-linux.img
options ${KERNEL_PARAMS}
EOF

        # Create fallback boot entry
        cat <<EOF > /boot/loader/entries/arch-fallback.conf
title Arch Linux (fallback initramfs)
linux /vmlinuz-linux
initrd ${MICROCODE_INITRD}
initrd /initramfs-linux-fallback.img
options ${KERNEL_PARAMS}
EOF
        
        echo -e "${GREEN}[OK]${NC} systemd-boot installed successfully"
        ;;
    2)
        # GRUB
        pacman -S grub --noconfirm
        if [[ "${ENCRYPTION_ENABLED}" == "true" ]]; then
            sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
            sed -i "s|^GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"cryptdevice=${ORIGINAL_ROOT}:cryptroot\"|" /etc/default/grub
        fi
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Arch Linux"
        grub-mkconfig -o /boot/grub/grub.cfg
        ;;
    3)
        # rEFInd
        pacman -S refind --noconfirm
        refind-install
        ;;
esac

BOOTLOADER_EOF

    # Add bootloader choice and other variables
    sed -i "s/\${BOOTLOADER_CHOICE}/$BOOTLOADER_CHOICE/g" /mnt/next.sh
    sed -i "s/\${ENCRYPTION_ENABLED}/$ENCRYPTION_ENABLED/g" /mnt/next.sh
    sed -i "s/\${ORIGINAL_ROOT}/${ORIGINAL_ROOT//\//\\/}/g" /mnt/next.sh
    
    # Set microcode initrd path based on CPU
    if [[ "$CPU_CHOICE" -eq 1 ]]; then
        sed -i "s/\${MICROCODE_INITRD}/\/amd-ucode.img/g" /mnt/next.sh
    elif [[ "$CPU_CHOICE" -eq 2 ]]; then
        sed -i "s/\${MICROCODE_INITRD}/\/intel-ucode.img/g" /mnt/next.sh
    else
        # No microcode
        sed -i "s/\${MICROCODE_INITRD}//g" /mnt/next.sh
    fi
    
    # Set root device for boot configuration
    if [[ "$ENCRYPTION_ENABLED" == true ]]; then
        sed -i "s/\${ROOT_DEVICE_FOR_BOOT}/\/dev\/mapper\/cryptroot/g" /mnt/next.sh
    else
        sed -i "s/\${ROOT_DEVICE_FOR_BOOT}/${ROOT//\//\\/}/g" /mnt/next.sh
    fi
}
# Add audio and driver configuration to post-install script
add_audio_drivers_config() {
    cat <<'AUDIO_EOF' >> /mnt/next.sh

# Audio system installation
echo -e "${YELLOW}[AUDIO]${NC} Installing audio system..."
if [[ ${AUDIO_CHOICE} -eq 1 ]]; then
    pacman -S pipewire pipewire-alsa pipewire-pulse pipewire-jack pavucontrol --noconfirm
    systemctl --user enable pipewire pipewire-pulse
else
    pacman -S pulseaudio pulseaudio-alsa pavucontrol --noconfirm
    systemctl --user enable pulseaudio
fi

# GPU driver installation
echo -e "${YELLOW}[GPU]${NC} Installing GPU drivers..."
case ${GPU_CHOICE} in
    1)
        # AMD
        pacman -S xf86-video-amdgpu mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
                 libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau --noconfirm
        ;;
    2)
        # Intel
        pacman -S xf86-video-intel mesa lib32-mesa vulkan-intel lib32-vulkan-intel \
                 intel-media-driver libva-intel-driver --noconfirm
        ;;
    3)
        # NVIDIA proprietary
        pacman -S nvidia nvidia-utils lib32-nvidia-utils nvidia-settings --noconfirm
        echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia.conf
        ;;
    4)
        # NVIDIA open-source
        pacman -S xf86-video-nouveau mesa lib32-mesa --noconfirm
        ;;
    5)
        # Multiple GPUs - install common packages
        pacman -S mesa lib32-mesa --noconfirm
        echo -e "${YELLOW}[INFO]${NC} Multiple GPU setup requires manual configuration."
        ;;
esac

AUDIO_EOF

    # Substitute variables
    sed -i "s/\${AUDIO_CHOICE}/$AUDIO_CHOICE/g" /mnt/next.sh
    sed -i "s/\${GPU_CHOICE}/$GPU_CHOICE/g" /mnt/next.sh
}
# Add desktop environment configuration
add_desktop_config() {
    cat <<'DESKTOP_EOF' >> /mnt/next.sh

# Desktop environment installation
echo -e "${YELLOW}[DE]${NC} Installing desktop environment..."
case ${DE_CHOICE} in
    1)
        # GNOME with essential packages
        pacman -S gnome-shell gnome-control-center gnome-terminal nautilus \
                 gnome-tweaks gnome-themes-extra gnome-backgrounds \
                 gnome-text-editor gnome-calculator gnome-calendar \
                 gnome-software file-roller xdg-desktop-portal-gnome \
                 gvfs gvfs-mtp gvfs-gphoto2 --noconfirm
        systemctl enable gdm
        ;;
    2)
        # KDE Plasma
        pacman -S plasma-desktop plasma-nm plasma-pa dolphin konsole \
                 kate spectacle gwenview ark okular kcalc --noconfirm
        systemctl enable sddm
        ;;
    3)
        # XFCE
        pacman -S xfce4 xfce4-goodies lightdm lightdm-gtk-greeter --noconfirm
        systemctl enable lightdm
        ;;
    4)
        # Hyprland (Wayland)
        pacman -S hyprland kitty wofi waybar grim slurp --noconfirm
        ;;
    5)
        # i3 (X11)
        pacman -S i3-wm i3status i3lock dmenu picom feh --noconfirm
        pacman -S xorg-server xorg-xinit --noconfirm
        ;;
    6)
        # Minimal - no DE
        echo -e "${BLUE}[INFO]${NC} Minimal installation - no desktop environment."
        ;;
esac

DESKTOP_EOF

    sed -i "s/\${DE_CHOICE}/$DE_CHOICE/g" /mnt/next.sh
}
# Add network and security configuration
add_network_security_config() {
    cat <<'NETWORK_EOF' >> /mnt/next.sh

# Network manager configuration
echo -e "${YELLOW}[NET]${NC} Configuring network manager..."
case ${NETWORK_MANAGER_CHOICE} in
    1)
        # NetworkManager
        systemctl enable NetworkManager
        ;;
    2)
        # systemd-networkd + iwd
        pacman -S iwd --noconfirm
        systemctl enable systemd-networkd systemd-resolved iwd
        ;;
    3)
        # wpa_supplicant (legacy)
        systemctl enable dhcpcd wpa_supplicant
        ;;
esac

# Security configuration
echo -e "${YELLOW}[SEC]${NC} Configuring security features..."
case ${SECURITY_CHOICE} in
    1)
        # Full security suite
        pacman -S ufw apparmor fail2ban --noconfirm
        systemctl enable ufw apparmor fail2ban
        ufw default deny incoming
        ufw default allow outgoing
        ufw enable
        systemctl enable apparmor
        ;;
    2)
        # Basic firewall only
        systemctl enable ufw
        ufw default deny incoming
        ufw default allow outgoing
        ufw enable
        ;;
    3)
        echo -e "${BLUE}[INFO]${NC} No additional security features enabled."
        ;;
esac

NETWORK_EOF

    sed -i "s/\${NETWORK_MANAGER_CHOICE}/$NETWORK_MANAGER_CHOICE/g" /mnt/next.sh
    sed -i "s/\${SECURITY_CHOICE}/$SECURITY_CHOICE/g" /mnt/next.sh
}
# Add system optimization and final configuration
add_optimization_config() {
    cat <<'OPTIMIZATION_EOF' >> /mnt/next.sh

# System optimization
echo -e "${YELLOW}[OPT]${NC} Applying system optimizations..."

# Enable zRAM for better memory management
pacman -S zram-generator --noconfirm
cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# Configure pacman for better performance
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

# Enable useful services
systemctl enable systemd-timesyncd
systemctl enable fstrim.timer

# Create user directories
pacman -S xdg-user-dirs --noconfirm

# Final system update
pacman -Syu --noconfirm

# Set up automatic mirror updates
cat <<EOF > /etc/systemd/system/reflector.service
[Unit]
Description=Update pacman mirrorlist
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/reflector --country 'Netherlands' --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

[Install]
WantedBy=multi-user.target
EOF

systemctl enable reflector.timer

echo -e "${GREEN}[COMPLETE]${NC} Post-installation configuration finished!"
OPTIMIZATION_EOF
}
# Main execution flow
main() {
    echo -e "${GREEN}[START]${NC} Arch Linux Enhanced Installation Script v${SCRIPT_VERSION}"
    echo -e "${BLUE}[INFO]${NC} This script will install Arch Linux with modern security and features."
    echo
    
    # Initial setup
    setup_logging
    check_system_requirements
    check_internet
    
    # Configuration phase
    echo -e "${YELLOW}[PHASE 1]${NC} System Configuration"
    select_disk_type
    select_partitions
    setup_encryption
    select_filesystem
    configure_user
    configure_system
    
    echo -e "${YELLOW}[PHASE 2]${NC} Component Selection"
    select_network_manager
    select_audio_system
    select_desktop_environment
    select_cpu_type
    select_gpu_driver
    select_bootloader
    select_display_manager
    select_security_options
    
    # Installation phase
    echo -e "${YELLOW}[PHASE 3]${NC} Installation"
    prepare_disks
    install_base_system
    
    # Post-install configuration
    echo -e "${YELLOW}[PHASE 4]${NC} Post-Installation Setup"
    create_post_install_script
    add_bootloader_config
    add_audio_drivers_config
    add_desktop_config
    add_network_security_config
    add_optimization_config
    
    # Execute post-install script
    show_progress 9 10 "Running post-installation configuration..."
    chmod +x /mnt/next.sh
    arch-chroot /mnt /next.sh
    
    show_progress 10 10 "Installation complete!"
    
    echo
    echo -e "${GREEN}[SUCCESS]${NC} Arch Linux installation completed successfully!"
    echo -e "${BLUE}[INFO]${NC} System is ready to reboot."
    echo -e "${YELLOW}[NEXT]${NC} After reboot:"
    if [[ "$ENCRYPTION_ENABLED" == true ]]; then
        echo "  - Enter your encryption passphrase at boot"
    fi
    echo "  - Login with username: ${USER}"
    echo "  - Check system status with: systemctl status"
    echo
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi