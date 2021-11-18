mkdir -p ~root/.ssh
cp ~vagrant/.ssh/auth* ~root/.ssh
yum install -y mdadm smartmontools hdparm gdisk
# Making raid 
mdadm --zero-superblock --force /dev/sd{b,c,d,e,f}
mdadm --create --verbose /dev/md0 -l 5 -n 5 /dev/sd{b,c,d,e,f}
# Creating mdadm config file
mkdir /etc/mdadm
echo "DEVICE partitions" > /etc/mdadm/mdadm.conf
mdadm --detail --scan --verbose | awk '/ARRAY/ {print}' >> /etc/mdadm/mdadm.conf
# Making partiotions
parted -s /dev/md0 mklabel gpt
parted /dev/md0 mkpart primary ext4 0% 20%
parted /dev/md0 mkpart primary ext4 20% 40%
parted /dev/md0 mkpart primary ext4 40% 60%
parted /dev/md0 mkpart primary ext4 60% 80%
parted /dev/md0 mkpart primary ext4 80% 100%
# Making filesystem
for i in $(seq 1 5); do mkfs.ext4 /dev/md0p$i; done
# Mounting block devices to mounting points
mkdir -p /raid/part{1,2,3,4,5}
for i in $(seq 1 5); do mount /dev/md0p$i /raid/part$i; done
# Altering /etc/fstab file to mount disks after reboot
for i in $(seq 1 5)
do
  echo "UUID=$(ls -l /dev/disk/by-uuid/ | grep md0p$i |  tr -s ' ' | cut -d " " -f 9) /raid/rand$i ext4 defaults 0 0" >> /etc/fstab
done
