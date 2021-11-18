# Домашнее задание 2

## Задание 2.1
### Требуется
Собрать собрать систему с подключенным рейдом и смонтированными разделоми. После перезагрузки разделы должны автоматически примонтироваться
### Выполнение
Написан Vagrantfile и скрипт провижининга script.sh, выполняющие требования.
[hw2.1/Vagrantfile](hw2.1/Vagrantfile)

[hw2.1/script.sh](hw2.1/script.sh)
## Задание 2.2
### Требуется
Перенести работающую систему с одним диском на RAID1. Даунтайм на загрузку с нового диска предполагается. 
### Выполнение
#### Подготовка Vagrantfile
Допустим мы имеек систему из образа centos/7. Отключен SELinux (иначе потребуется больше перезагрузок). 
Подключим к системе еще один IDE диск, такого же размера (40G).
Будем собирать RAID1 из существующего диска и нового.
#### Скрипты для автосборки 
[hw2.2/Vagrantfile](hw2.2/Vagrantfile)

[hw2.2/stage-1.sh](hw2.2/stage-1.sh)

[hw2.2/stage-2.sh](hw2.2/stage-2.sh)
#### Процесс ручного переноса системы на RAID1.
Получаем список блочных устройств:
```
[root@otuslinux ~]# lsblk
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda      8:0    0  40G  0 disk 
└─sda1   8:1    0  40G  0 part /
sdb      8:16   0  40G  0 disk 
```

Получаем информацию о файловых системах:

```
[root@otuslinux ~]# blkid
/dev/sda1: UUID="1c419d6c-5064-4a2b-953c-05b2c67edb15" TYPE="xfs" 
```

Получаем информацию о разделах:

```
[root@otuslinux ~]# fdisk -l

Disk /dev/sda: 42.9 GB, 42949672960 bytes, 83886080 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x0009ef1a

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048    83886079    41942016   83  Linux

Disk /dev/sdb: 42.9 GB, 42949672960 bytes, 83886080 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```

Новый диск `sdb`. Начнем собирать RAID1.

Поскольку диск `sda` имеет один dos-раздел `sda1`, создадим аналогичный на `sdb`

```
[root@otuslinux ~]# parted -s /dev/sdb mklabel msdos
[root@otuslinux ~]# parted -s /dev/sdb mkpart primary xfs 0% 100%
[root@otuslinux ~]# parted -s /dev/sdb set 1 raid on
```

Мы включили парамерт `raid`, для автоматического определения рейда на этапе загрузки системы.

Проверяем, что получилось:
```
[root@otuslinux ~]# lsblk
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
sda      8:0    0  40G  0 disk 
└─sda1   8:1    0  40G  0 part /
sdb      8:16   0  40G  0 disk 
└─sdb1   8:17   0  40G  0 part 
```
Будем объединять в RAID1 блочные устройства `/dev/sda1` и `/dev/sdb1`

Сначала добавим в рейд только диск `/dev/sdb1`:
```
[root@otuslinux ~]# mdadm --create --verbose /dev/md0 -l 1 -n 2 missing /dev/sdb1 --metadata=0.90
```

Параметр `--metadata=0.90` - для работы с dos разделами.

Проверим, что получилось:
```
[root@otuslinux ~]# lsblk
NAME    MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda       8:0    0  40G  0 disk  
└─sda1    8:1    0  40G  0 part  /
sdb       8:16   0  40G  0 disk  
└─sdb1    8:17   0  40G  0 part  
  └─md0   9:0    0  40G  0 raid1 
[root@otuslinux ~]# cat /proc/mdstat
Personalities : [raid1] 
md0 : active raid1 sdb1[1]
      41941952 blocks [2/1] [_U]
      
unused devices: <none>
```
Создаем файловую систему `xfs` на устройстве `/dev/md0` и монтируем ена в `/mnt`:

```
[root@otuslinux ~]# mkfs.xfs /dev/md0
[root@otuslinux ~]# mount /dev/md0 /mnt
```
Теперь нужно перенести файлы существующей системы на новый раздел. Делать это будем с помощью утилиты `rsync` с параметрами:
`-a` - archive mode.
`-x` - Чтобы не копировать динамический контент в каталогах `/run`, `/proc`,` /dev`, `/sys`

```
[root@otuslinux ~]# rsync -a -x / /mnt/
```
Смонтируем каталоги`/run`, `/proc`,` /dev`, `/sys` в новую файловую систему:

```
[root@otuslinux ~]# mount --bind /dev /mnt/dev/
[root@otuslinux ~]# mount --bind /run /mnt/run/
[root@otuslinux ~]# mount --bind /sys /mnt/sys/
[root@otuslinux ~]# mount --bind /proc /mnt/proc/
```
Теперь нужно настроить загрузку с новго раздела

Сменим root
```
[root@otuslinux ~]# chroot /mnt
[root@otuslinux /]#
```
Для автоматического определения RAID дисков на этапе загрузки изменим конфиг GRUB2
```
GRUB_CMDLINE_LINUX="rd.auto rd.auto=1 rhgb"
```
`rd.auto rd.auto=1` - обеспечит автоопределение RAID на этапе загрузки
`rhgb` - просто цветной вывод процесса загрузки

Обеспечим монтирование в `/` нового устройства `/dev/md0` по его uuid
Узнаем UUID
```bash
[root@otuslinux /]# blkid
/dev/sda1: UUID="1c419d6c-5064-4a2b-953c-05b2c67edb15" TYPE="xfs" 
/dev/sdb1: UUID="f37073d7-cb39-006b-8ed4-a3a19f626544" TYPE="linux_raid_member" 
/dev/md0: UUID="e98d2d94-c1bc-490a-8d04-3efd757298c5" TYPE="xfs" 
```
Отредактируем `/etc/fstab`
```
vi /etc/fstab
```
Было:
```
#
# /etc/fstab
# Created by anaconda on Thu Apr 30 22:04:55 2020
#
# Accessible filesystems, by reference, are maintained under '/dev/disk'
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info
#
UUID=1c419d6c-5064-4a2b-953c-05b2c67edb15 /                       xfs     defaults        0 0
/swapfile none swap defaults 0 0
#VAGRANT-BEGIN
# The contents below are automatically generated by Vagrant. Do not modify.
#VAGRANT-END

```
Стало:
```
#
# /etc/fstab
# Created by anaconda on Thu Apr 30 22:04:55 2020
#
# Accessible filesystems, by reference, are maintained under '/dev/disk'
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info
#
UUID=e98d2d94-c1bc-490a-8d04-3efd757298c5 /                       xfs     defaults        0 0
/swapfile none swap defaults 0 0
#VAGRANT-BEGIN
# The contents below are automatically generated by Vagrant. Do not modify.
#VAGRANT-END
```

Для загрузки модуля `mdadm` на этапе первоначальной загрузки системы будем использовать 
`initramfs`.
Создадим образ `initramfs` с помощью утилиты `dracut`.
Эта утилита автоматом определит используемые в данный момент модули и добавит их в `initramfs`.
```
[root@otuslinux /]# cp /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.bck
[root@otuslinux /]# dracut --force /boot/initramfs-$(uname -r).img $(uname -r) -M
```

Теперь можно устанавливать GRUB2 на новый диск.

```
[root@otuslinux /]# grub2-mkconfig -o /etc/grub2.cfg
Generating grub configuration file ...
...
...
...
done
[root@otuslinux /]# grub2-install /dev/sdb
Installing for i386-pc platform.
...
...
...
Installation finished. No error reported.
```
Важно устанавливать GRUB2 именно на блочное устройсво `/dev/sdb`

Можно перезагружаться, выбрав новый диск для загрузки.

После перезагрузки смотри, что получилось
```
[root@otuslinux ~]# lsblk
NAME    MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda       8:0    0  40G  0 disk  
└─sda1    8:1    0  40G  0 part  
sdb       8:16   0  40G  0 disk  
└─sdb1    8:17   0  40G  0 part  
  └─md0   9:0    0  40G  0 raid1 /
[root@otuslinux ~]# cat /proc/mdstat
Personalities : [raid1] 
md0 : active raid1 sdb1[1]
      41941952 blocks [2/1] [_U]
      
unused devices: <none>
```
Осталось добавить раздел `/dev/sda1` в RAID
[root@otuslinux ~]# mdadm --manage /dev/md0 --add /dev/sda1
mdadm: hot added /dev/sda1

Подождем процесса сборки RAID 
```
[root@otuslinux ~]# cat /proc/mdstat
Personalities : [raid1] 
md0 : active raid1 sda1[2] sdb1[1]
      41941952 blocks [2/1] [_U]
      [===>.................]  recovery = 15.2% (6404224/41941952) finish=2.9min speed=200132K/sec
      
unused devices: <none>
```

Установим GRUB на `/dev/sda`:

```
[root@otuslinux ~]# grub2-install /dev/sda
```

Готово!
```
[root@otuslinux ~]# cat /proc/mdstat
Personalities : [raid1] 
md0 : active raid1 sda1[0] sdb1[1]
      41941952 blocks [2/2] [UU]
      
unused devices: <none>
[root@otuslinux ~]# lsblk
NAME    MAJ:MIN RM SIZE RO TYPE  MOUNTPOINT
sda       8:0    0  40G  0 disk  
└─sda1    8:1    0  40G  0 part  
  └─md0   9:0    0  40G  0 raid1 /
sdb       8:16   0  40G  0 disk  
└─sdb1    8:17   0  40G  0 part  
  └─md0   9:0    0  40G  0 raid1 /
[root@otuslinux ~]# fdisk -l

Disk /dev/sda: 42.9 GB, 42949672960 bytes, 83886080 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x0009ef1a

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *        2048    83886079    41942016   83  Linux

Disk /dev/sdb: 42.9 GB, 42949672960 bytes, 83886080 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk label type: dos
Disk identifier: 0x000a55c4

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1            2048    83886079    41942016   fd  Linux raid autodetect

Disk /dev/md0: 42.9 GB, 42948558848 bytes, 83883904 sectors
Units = sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
```
