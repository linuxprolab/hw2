#! /bin/bash 
export TERM=xterm
sudo -i
# Partitioning new drive
parted -s /dev/sdb mklabel msdos
parted -s /dev/sdb mkpart primary xfs 0% 100%
parted -s /dev/sdb set 1 raid on

# Making RAID1 with 1 device
mdadm --create --verbose /dev/md0 -l 1 -n 2 missing /dev/sdb1 --metadata=0.90

# Making and mountinng fs to /mnt
mkfs.xfs /dev/md0
mount /dev/md0 /mnt

# Copying system to new md0
rsync -a -x / /mnt/

# Changing root to /mnt with binding nessary things
mount --bind /dev /mnt/dev/
mount --bind /run /mnt/run/
mount --bind /sys /mnt/sys/
mount --bind /proc /mnt/proc/
chroot /mnt /bin/bash << "EOT"

# Get new uuid for / and alter /etc/fstab 
MD0=$(ls -l /dev/disk/by-uuid/ | grep md0 | tr -s ' ' |  cut -d " " -f 9)
SDA1=$(ls -l /dev/disk/by-uuid/ | grep sda1 | tr -s ' ' |  cut -d " " -f 9)
sed -i -e 's/'"$SDA1"'/'"$MD0"'/g' /etc/fstab

# Modifyind default grub config
echo "GRUB_CMDLINE_LINUX=\"rd.auto rd.auto=1 rhgb\"" >> /etc/default/grub
# rd.auto rd.auto=1 to detect raid disk
# rhgb to colored booting

# make new initramfs using dracut. it adds mdadm module to enable raid properly while booting
cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bck
dracut --force /boot/initramfs-$(uname -r).img $(uname -r) -M
# Install grub
grub2-mkconfig -o /etc/grub2.cfg
grub2-install /dev/sdb
EOT
# exit chroot and reboot
reboot

