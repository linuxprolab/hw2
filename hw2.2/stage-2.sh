# Install GRUB to /dev/sda
grub2-install /dev/sda
mmdadm --manage /dev/md0 --add /dev/sda1
cat /proc/mdstat
# wait till recovery ends
# FINISH!!!

