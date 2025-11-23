basestrap /mnt base base-devel openrc elogind-openrc
basestrap /mnt linux linux-firmware sof-firmware nvim efibootmgr \
  dhcpcd-openrc dhcpcd iwd iwd-openrc

basestrap /mnt dosfstools btrfs-progs e2fsprogs \
  cryptsetup cryptsetup-openrc intel-ucode
