mount /dev/mapper/cryptroot /mnt

# Create subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots

# Unmount to remount with proper structure
umount /mnt

# Mount root subvolume
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt

# Create mount points
mkdir -p /mnt/{home,var,tmp,.snapshots,boot}

# Mount other subvolumes
mount -o compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o compress=zstd,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o compress=zstd,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
mount -o compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
