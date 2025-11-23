#!/bin/bash
#
# Artix Linux Automated Installation Script
# EFISTUB + Btrfs + LUKS2 + OpenRC
#
# WARNING: This script will DESTROY all data on the selected disk!
# Use at your own risk. Always backup your data first.
#

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Banner
print_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        Artix Linux Automated Installation Script         ║
║                                                           ║
║    EFISTUB + Btrfs + LUKS2 + OpenRC + Suckless Tools     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
    fi
}

# Check UEFI mode
check_uefi() {
    log_info "Checking UEFI boot mode..."
    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        log_error "System not booted in UEFI mode. This script requires UEFI."
    fi
    log_success "UEFI mode confirmed"
}

# Check internet connectivity
check_internet() {
    log_info "Checking internet connectivity..."
    if ! ping -c 3 artixlinux.org &> /dev/null; then
        log_error "No internet connection. Please configure network first."
    fi
    log_success "Internet connection established"
}

# Update system clock
update_clock() {
    log_info "Synchronizing system clock..."
    ntpd -q -g || log_warning "Failed to sync time, continuing anyway..."
}

# List available disks
list_disks() {
    echo ""
    log_info "Available disks:"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE,TRAN | grep disk
    echo ""
}

# Detect disk type (nvme or regular)
get_partition_naming() {
    local disk=$1
    if [[ $disk == *"nvme"* ]]; then
        echo "p"  # NVMe uses p1, p2 notation
    else
        echo ""   # Regular disks use sda1, sda2 notation
    fi
}

# Get user input for disk selection
select_disk() {
    list_disks
    
    while true; do
        read -p "Enter target disk (e.g., sda, nvme0n1): " DISK
        DISK_PATH="/dev/${DISK}"
        
        if [[ ! -b $DISK_PATH ]]; then
            log_error "Invalid disk: $DISK_PATH does not exist"
            continue
        fi
        
        # Get partition naming convention
        PART_SEP=$(get_partition_naming "$DISK")
        EFI_PART="${DISK_PATH}${PART_SEP}1"
        ROOT_PART="${DISK_PATH}${PART_SEP}2"
        
        echo ""
        log_warning "Selected disk: $DISK_PATH"
        log_warning "EFI partition will be: $EFI_PART"
        log_warning "Root partition will be: $ROOT_PART"
        echo ""
        log_error "ALL DATA ON $DISK_PATH WILL BE DESTROYED!"
        echo ""
        
        read -p "Type 'YES' in capital letters to confirm: " confirm
        if [[ "$confirm" == "YES" ]]; then
            break
        else
            log_info "Disk selection cancelled. Please select again."
        fi
    done
}

# Get system configuration
get_system_config() {
    echo ""
    log_info "System Configuration"
    echo ""
    
    # Hostname
    read -p "Enter hostname [artix]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-artix}
    
    # Username
    read -p "Enter username [dark]: " USERNAME
    USERNAME=${USERNAME:-dark}
    
    # Timezone
    read -p "Enter timezone [Europe/Berlin]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-Europe/Berlin}
    
    # Locale
    read -p "Enter locale [en_US.UTF-8]: " LOCALE
    LOCALE=${LOCALE:-en_US.UTF-8}
    
    # CPU vendor
    echo ""
    echo "Select CPU vendor:"
    echo "1) Intel"
    echo "2) AMD"
    read -p "Enter choice [1]: " cpu_choice
    cpu_choice=${cpu_choice:-1}
    
    if [[ $cpu_choice == "2" ]]; then
        MICROCODE="amd-ucode"
    else
        MICROCODE="intel-ucode"
    fi
    
    # LUKS parameters
    echo ""
    log_info "LUKS2 Encryption Parameters"
    echo ""
    read -p "PBKDF memory in MB [4096]: " LUKS_MEMORY
    LUKS_MEMORY=${LUKS_MEMORY:-4096}
    LUKS_MEMORY_KB=$((LUKS_MEMORY * 1024))
    
    read -p "PBKDF parallel threads [4]: " LUKS_PARALLEL
    LUKS_PARALLEL=${LUKS_PARALLEL:-4}
    
    read -p "Iteration time in ms [4000]: " LUKS_ITER_TIME
    LUKS_ITER_TIME=${LUKS_ITER_TIME:-4000}
    
    log_success "Configuration completed"
}

# Partition the disk
partition_disk() {
    log_info "Partitioning disk $DISK_PATH..."
    
    # Wipe any existing filesystem signatures
    wipefs -af "$DISK_PATH" || true
    
    # Create GPT partition table and partitions
    sgdisk -Z "$DISK_PATH" || true
    sgdisk -o "$DISK_PATH"
    sgdisk -n 1:0:+512M -t 1:EF00 -c 1:"EFI System" "$DISK_PATH"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux Root" "$DISK_PATH"
    
    # Inform kernel of partition changes
    partprobe "$DISK_PATH"
    sleep 2
    
    log_success "Disk partitioned successfully"
}

# Setup LUKS encryption
setup_encryption() {
    log_info "Setting up LUKS2 encryption..."
    log_warning "You will be prompted to enter your encryption passphrase"
    echo ""
    
    cryptsetup luksFormat --batch-mode --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        --pbkdf-memory "$LUKS_MEMORY_KB" \
        --pbkdf-parallel "$LUKS_PARALLEL" \
        --iter-time "$LUKS_ITER_TIME" \
        "$ROOT_PART"
    
    log_info "Opening encrypted container..."
    cryptsetup open "$ROOT_PART" cryptroot
    
    log_success "LUKS encryption configured"
}

# Create Btrfs filesystem and subvolumes
setup_btrfs() {
    log_info "Creating Btrfs filesystem..."
    mkfs.btrfs -f -L "Artix Linux" /dev/mapper/cryptroot
    
    # Mount and create subvolumes
    mount /dev/mapper/cryptroot /mnt
    
    log_info "Creating Btrfs subvolumes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@snapshots
    
    umount /mnt
    
    log_success "Btrfs filesystem created"
}

# Mount filesystems
mount_filesystems() {
    log_info "Mounting filesystems..."
    
    # Mount options
    MOUNT_OPTS="compress=zstd,noatime,space_cache=v2"
    
    # Mount root subvolume
    mount -o "${MOUNT_OPTS},subvol=@" /dev/mapper/cryptroot /mnt
    
    # Create mount points
    mkdir -p /mnt/{home,var,tmp,.snapshots,boot}
    
    # Mount other subvolumes
    mount -o "${MOUNT_OPTS},subvol=@home" /dev/mapper/cryptroot /mnt/home
    mount -o "${MOUNT_OPTS},subvol=@var" /dev/mapper/cryptroot /mnt/var
    mount -o "${MOUNT_OPTS},subvol=@tmp" /dev/mapper/cryptroot /mnt/tmp
    mount -o "${MOUNT_OPTS},subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
    
    # Format and mount EFI partition
    mkfs.vfat -F 32 "$EFI_PART"
    mount "$EFI_PART" /mnt/boot
    
    log_success "Filesystems mounted"
}

# Install base system
install_base() {
    log_info "Installing base system (this may take a while)..."
    
    basestrap /mnt base base-devel openrc elogind-openrc
    basestrap /mnt linux linux-firmware sof-firmware
    basestrap /mnt nvim efibootmgr dhcpcd-openrc dhcpcd iwd iwd-openrc
    basestrap /mnt dosfstools btrfs-progs e2fsprogs cryptsetup cryptsetup-openrc
    basestrap /mnt "$MICROCODE"
    
    log_success "Base system installed"
}

# Generate fstab
generate_fstab() {
    log_info "Generating fstab..."
    fstabgen -U /mnt >> /mnt/etc/fstab
    log_success "fstab generated"
}

# Configure system in chroot
configure_system() {
    log_info "Configuring system..."
    
    # Create configuration script
    cat > /mnt/root/configure.sh << EOFCONFIG
#!/bin/bash
set -e

# Set timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Configure locale
echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=\"${LOCALE}\"" > /etc/locale.conf

# Set hostname
sed -i "s/hostname='localhost'/hostname='${HOSTNAME}'/" /etc/conf.d/hostname
echo "${HOSTNAME}" > /etc/hostname
echo "127.0.1.1        ${HOSTNAME}.localdomain  ${HOSTNAME}" >> /etc/hosts

# Set root password
echo "Set root password:"
passwd

# Create user
useradd -m -G wheel,storage,power,audio,video -s /bin/bash ${USERNAME}
echo "Set password for user ${USERNAME}:"
passwd ${USERNAME}

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Configure mkinitcpio
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Enable services
rc-update add dhcpcd default
rc-update add iwd default
rc-update add elogind default

echo "Configuration completed successfully"
EOFCONFIG
    
    chmod +x /mnt/root/configure.sh
    artix-chroot /mnt /root/configure.sh
    rm /mnt/root/configure.sh
    
    log_success "System configured"
}

# Setup EFISTUB boot entry
setup_efistub() {
    log_info "Setting up EFISTUB boot entry..."
    
    # Get UUIDs
    LUKS_UUID=$(blkid -o value -s UUID "$ROOT_PART")
    ROOT_UUID=$(blkid -o value -s UUID /dev/mapper/cryptroot)
    
    log_info "LUKS UUID: $LUKS_UUID"
    log_info "Root UUID: $ROOT_UUID"
    
    # Determine microcode image name
    if [[ $MICROCODE == "intel-ucode" ]]; then
        UCODE_IMG="intel-ucode.img"
    else
        UCODE_IMG="amd-ucode.img"
    fi
    
    # Create boot entry
    artix-chroot /mnt /bin/bash << EOFBOOT
efibootmgr --create \
    --disk ${DISK_PATH} \
    --part 1 \
    --label "Artix Linux" \
    --loader /vmlinuz-linux \
    --unicode "cryptdevice=UUID=${LUKS_UUID}:cryptroot root=UUID=${ROOT_UUID} rootflags=subvol=@ rw loglevel=3 quiet initrd=\\${UCODE_IMG} initrd=\\initramfs-linux.img" \
    --verbose

# Create fallback entry
efibootmgr --create \
    --disk ${DISK_PATH} \
    --part 1 \
    --label "Artix Linux (Fallback)" \
    --loader /vmlinuz-linux \
    --unicode "cryptdevice=UUID=${LUKS_UUID}:cryptroot root=UUID=${ROOT_UUID} rootflags=subvol=@ rw initrd=\\${UCODE_IMG} initrd=\\initramfs-linux-fallback.img" \
    --verbose

efibootmgr -v
EOFBOOT
    
    log_success "EFISTUB boot entries created"
}

# Install post-installation packages
install_post_packages() {
    log_info "Installing additional packages..."
    
    artix-chroot /mnt /bin/bash << 'EOFPKG'
pacman -Syu --needed --noconfirm \
    xorg xorg-xinit \
    git wget curl \
    man-db man-pages \
    bash-completion \
    rsync unzip zip \
    xdg-utils \
    firefox
EOFPKG
    
    log_success "Additional packages installed"
}

# Setup suckless tools
setup_suckless() {
    log_info "Setting up suckless tools..."
    
    artix-chroot /mnt /bin/bash << EOFSUCKLESS
# Switch to user home
su - ${USERNAME} << 'EOFUSER'
cd ~/
mkdir -p artix-dotfiles
cd artix-dotfiles

# Clone suckless software
git clone git://git.suckless.org/dwm
git clone git://git.suckless.org/st
git clone git://git.suckless.org/dmenu

# Build and install dwm
cd dwm
sudo make clean install

# Build and install st
cd ../st
sudo make clean install

# Build and install dmenu
cd ../dmenu
sudo make clean install

# Create .xinitrc
cd ~/
echo 'exec dwm' > .xinitrc

echo "Suckless tools installed successfully"
EOFUSER
EOFSUCKLESS
    
    log_success "Suckless tools configured"
}

# Cleanup and unmount
cleanup() {
    log_info "Cleaning up..."
    
    umount -R /mnt || true
    cryptsetup close cryptroot || true
    
    log_success "Cleanup completed"
}

# Main installation function
main() {
    print_banner
    
    log_info "Starting Artix Linux installation..."
    echo ""
    
    # Pre-flight checks
    check_root
    check_uefi
    check_internet
    update_clock
    
    # Get configuration
    select_disk
    get_system_config
    
    # Confirmation
    echo ""
    log_warning "=== Installation Summary ==="
    echo "Disk: $DISK_PATH"
    echo "EFI Partition: $EFI_PART"
    echo "Root Partition: $ROOT_PART"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    echo "Microcode: $MICROCODE"
    echo "LUKS Memory: ${LUKS_MEMORY}MB"
    echo ""
    
    read -p "Proceed with installation? (yes/no): " final_confirm
    if [[ "$final_confirm" != "yes" ]]; then
        log_error "Installation cancelled by user"
    fi
    
    # Installation steps
    partition_disk
    setup_encryption
    setup_btrfs
    mount_filesystems
    install_base
    generate_fstab
    configure_system
    setup_efistub
    install_post_packages
    setup_suckless
    cleanup
    
    # Success message
    echo ""
    log_success "╔═══════════════════════════════════════════════════════╗"
    log_success "║                                                       ║"
    log_success "║      Artix Linux installation completed!             ║"
    log_success "║                                                       ║"
    log_success "║  Remove installation media and reboot:               ║"
    log_success "║  # reboot                                             ║"
    log_success "║                                                       ║"
    log_success "║  After boot, start X11 with:                         ║"
    log_success "║  $ startx                                             ║"
    log_success "║                                                       ║"
    log_success "╚═══════════════════════════════════════════════════════╝"
    echo ""
}

# Error handling
trap 'log_error "Installation failed at line $LINENO"' ERR

# Run main function
main "$@"
