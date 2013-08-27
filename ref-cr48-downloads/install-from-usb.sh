#!/bin/bash
#make sure it runs from bash on chronos 

# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.

#install-data.sh derived from install-ubuntu-1204-9.sh
#to be run on an acer c7 installing from a usb stick data/ directory.

cfg_install_to=/dev/mmcblk0
cfg_install_from=/dev/sdb1

fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    return
  else
    echo -e "\nOh good. You're running a developer BIOS...\n"
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"
    #PARROT PUFFIN F-D 0168

echo -e "Chome OS model is: $hwid\n"

chromebook_arch="`uname -m`"
    #i686
if [ ! "$chromebook_arch" = "x86_64" ]
then
  echo -e "This version of Chrome OS isn't 64-bit. We'll use an unofficial Chromium OS kernel to get around this...\n"
else
  echo -e "and you're running a 64-bit version of Chrome OS! That's just dandy!\n"
fi

read -p "Press [Enter] to continue..."

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

powerm_status="`initctl status powerm`"
if [ ! "$powerm_status" = "powerm stop/waiting" ]
then
  echo -e "Stopping powerm to keep display from timing out..."
  initctl stop powerm
fi

setterm -blank 0

if [ "$cfg_install_to" != "" ]; then
  target_disk=$cfg_install_to
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
  parted --script ${target_disk} "mktable gpt"
  cgpt create ${target_disk} 
  cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
  cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
  sync
  blockdev --rereadpt ${target_disk}
  partprobe ${target_disk}
  crossystem dev_boot_usb=1
else
    target_disk="`rootdev -d -s`"
    echo "ERROR: not allowed to install to $target_disk"
    exit
fi

target_repo=/mnt/stateful_partition/ubuntu
if [ ! -d $target_repo ]; then
  mkdir $target_repo
fi

cd $target_repo

# try mounting a USB / SD Card if it's there...
if [ ! -d /tmp/usb_files ]; then
    mkdir /tmp/usb_files
fi

umount /dev/sdb1                > /dev/null 2>&1
mount  /dev/sdb1 /tmp/usb_files > /dev/null 2>&1

if [ ! -d /tmp/usb_files/ubuntu ]; then 
    echo "ERROR: no ubuntu dir on usb drive /dev/sdb1"
    exit 1
fi

# Copy /tmp/usb_files/ubuntu (.sha1 and foo.6 files) to SSD if they're there
if [ -d /tmp/usb_files/ubuntu ]; then
    if [ ! -d $target_repo/data ]; then
        echo "Copying all ubuntu/* files to stateful_partition/ubuntu/"
        cp -rf /tmp/usb_files/ubuntu/* $target_repo/
    else 
        echo "Using ubuntu/* files in stateful_partition/ubuntu/"
    fi
else
    echo "ERROR: no ubuntu/data dir on usb drive /dev/sdb1"
    exit 1
fi

if [[ "${target_disk}" =~ "mmcblk" ]]; then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
    echo "ERROR: not allowed to install to non-mmcblk device"
    exit 1
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"
if grep mmcblk /proc/mounts ; then
    echo "ERROR: mmcblk mounted"
    exit 1
fi

debug_skip_rootfs=1
# Download and copy ubuntu root filesystem, keep track of successful parts so we can resume
SEEK=0
FILESIZE=102400
for one in a b; do
  for two in a b c d e f g h i j k l m n o p q r s t u v w x y z;   do
    # last file is smaller than the rest...
    if [ "$one$two" = "bz" ]; then
      FILESIZE=20480
    fi
    if [ $debug_skip_rootfs -ne 0 ]; then 
        echo "DEBUG: Skip  $one  $two "
        continue
    fi
    FILENAME="ubuntu-1204.bin$one$two.bz2"
      if [ ! -f $target_repo/data/$FILENAME.sha1 ]; then
          echo "ERROR: no file $FILENAME.sha1"
          exit 1
      fi
      correct_sha1=`cat $target_repo/data/$FILENAME.sha1 | awk '{print $1}'`
      correct_sha1_length="${#correct_sha1}"
      if [ "$correct_sha1_length" -eq "40" ]; then
        correct_sha1_is_valid=1
      else
          echo "ERROR: wrong file $FILENAME.sha1"
          exit 1
      fi
    current_sha1=`dd if=${target_rootfs} bs=1024 skip=$SEEK count=$FILESIZE status=noxfer | sha1sum | awk '{print $1}'`
    if [ "$correct_sha1" = "$current_sha1" ]; then
        echo "$correct_sha1 equals $current_sha1 already written correctly..."
        SEEK=$(( $SEEK + $FILESIZE ))
        continue
    else
        echo -e "$FILENAME needs to be written because it's $current_sha1 not $correct_sha1"
    fi
    if [ -f $target_repo/data/$FILENAME ]; then
        echo -e "Found $FILENAME on flash drive. Using it..."
        get_cmd="cat $target_repo/data/$FILENAME"
    else
          echo "ERROR: no file $FILENAME"
          exit 1
    fi
        $get_cmd | bunzip2 -c | dd bs=1024 seek=$SEEK of=${target_rootfs} status=noxfer > /dev/null 2>&1
        current_sha1=`dd if=${target_rootfs} bs=1024 skip=$SEEK count=$FILESIZE status=noxfer | sha1sum | awk '{print $1}'`
        if [ "$correct_sha1" = "$current_sha1" ]; then
            echo -e "\n$FILENAME was written to ${target_rootfs} correctly...\n\n"
        else
          echo -e "\nError writing file $FILENAME. shouldbe: $correct_sha1 is:$current_sha1. Retrying...\n\n"
          exit 1
        fi
    SEEK=$(( $SEEK + $FILESIZE ))
  done
done

#Mount Ubuntu rootfs and copy cgpt + modules over
echo "Copying modules, firmware and binaries to ${target_rootfs} for ChrUbuntu"
if [ ! -d /tmp/urfs ]; then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs
if [ ! -d /tmp/urfs/usr/bin ]; then
    echo -e "\nError mounted usb with no /usr/bin\n\n"
    exit 1
else
    echo "Mounted  ${target_rootfs}  to  /tmp/urfs"
fi
cp /usr/bin/cgpt /tmp/urfs/usr/bin/
chmod a+rx /tmp/urfs/usr/bin/cgpt
echo "Copied  cgpt"

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config
if [ "$chromebook_arch" = "x86_64" ]  # We'll use the official Chrome OS kernel if it's x64
then
    echo -e "\nError unexpected x86_64\n\n"
    exit 1
  cp -ar /lib/modules/* /tmp/urfs/lib/modules/
  vbutil_kernel --pack newkern \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config \
    --vmlinuz /boot/vmlinuz-`uname -r`
  use_kernfs=newkern
else # Otherwise we'll download a custom-built non-official Chromium OS kernel
  model="mario" # set a default
  if [[ $hwid =~ .*MARIO.* ]]
  then
    model="mario"
  else
    if [[ $hwid =~ .*ALEX.* ]]
    then
      model="alex"
    else
      if [[ $hwid =~ .*ZGB.* ]]
      then
        model="zgb"
      fi
    fi
  fi
  #wget http://cr-48-ubuntu.googlecode.com/files/$model-x64-modules.tar.bz2
  #wget http://cr-48-ubuntu.googlecode.com/files/$model-x64-kernel-partition.bz2
    echo "Check kernel"
    if [ -f $target_repo/data/$model-x64-kernel-partition.bz2 ]; then
        echo -e "Using $model kernel on flash drive..."
        cp $target_repo/data/$model-x64-kernel-partition.bz2 .
    else
          echo "ERROR: no kernel file for model $model"
          exit 1
    fi
    if [ -f $target_repo/data/$model-x64-modules.tar.bz2 ]; then
        echo -e "Using $model modules on flash drive..."
        cp $target_repo/data/$model-x64-modules.tar.bz2 .
    else
          echo "ERROR: no modules file"
          exit 1
    fi
  bunzip2 $model-x64-kernel-partition.bz2
  use_kernfs="$model-x64-kernel-partition"
  vbutil_kernel --repack $use_kernfs \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config
  tar xjvvf $model-x64-modules.tar.bz2 --directory /tmp/urfs/lib/modules
fi
umount /tmp/urfs

dd if=$use_kernfs of=${target_kern}






# Resize sda7 in order to "grow" filesystem to user's selected size
echo "Resize ${target_rootfs}"
e2fsck -f ${target_rootfs}
resize2fs -p ${target_rootfs}

#Set Ubuntu partition as top priority for next boot
echo "Set cgpt for disk ${target_disk}"
cgpt add -i 6 -P 5 -T 1 ${target_disk}

# reboot
echo "reboot now"
##reboot
