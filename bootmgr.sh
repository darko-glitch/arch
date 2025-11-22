#!/usr/bin/env bash

efibootmgr --create \
  --disk /dev/nvme0n1 \
  --part 1 \
  --label "Artix Linux" \
  --loader /vmlinuz-linux \
  --unicode "cryptdevice=UUID=$(blkid -o value -s UUID /dev/sda2):cryptroot root=UUID=$(blkid -o value -s UUID /dev/mapper/cryptroot) rootflags=subvol=@ rw loglevel=3 quiet initrd=\intel-ucode.img initrd=\initramfs-linux.img" \
  --verbose
