cryptsetup luksFormat --batch-mode --type luks2 \
  --cipher aes-xts-plain64 \
  --key-size 512 \
  --hash sha512 \
  --pbkdf argon2id \
  --pbkdf-memory 4194304 \
  --pbkdf-parallel 4 \
  --iter-time 4000 \
  /dev/sda2
