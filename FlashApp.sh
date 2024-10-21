#!/bin/sh

# Check and if exists, source these files /etc/include.properties and /etc/device.properties
if [ -f /etc/include.properties ]; then
    . /etc/include.properties
fi
if [ -f /etc/device.properties ]; then
    . /etc/device.properties
fi

if [ -z "$PERSISTENT_PATH" ]; then
    PERSISTENT_PATH=$(pwd)
fi
OUTPUT="$PERSISTENT_PATH/output.txt"
EXTBLOCK="$PERSISTENT_PATH/extblock"
WICIMAGEFILE="$PERSISTENT_PATH/wicimage"

logger() {
    echo "$(date) FlashApp.sh > $1" | tee -a $OUTPUT
}

# Check if all the commands used in this script are available
commandsRequired="umount df grep tail cut head fdisk mount umount cp rm mkdir sed reboot stat tee date tar read"
for cmd in $commandsRequired; do
    if ! command -v $cmd > /dev/null; then
        logger "Required command '$cmd' not found; cannot proceed, exiting."
        exit 1
    fi
done

# This script can be invoked with 2 arguments or 1 argument. Handle both cases.
# 1. /usr/bin/FlashApp "$DOWNLOAD_LOCATION/$UPGRADE_FILE"
# 2. /usr/bin/FlashApp "$DOWNLOAD_LOCATION" "$UPGRADE_FILE"
if [ $# -eq 2 ]; then
    cloudFWFile=$1/$2
    logger "Firmware image file is passed as two arguments"
elif [ $# -eq 1 ]; then
    cloudFWFile=$1
    logger "Firmware image file is passed as one argument"
else
    logger "Invalid number of arguments passed"
    echo "Usage: $0 <Absolute path to Firmware Image File>"
    exit 1
fi

# RPI OTA image is a compressed file; extract it if so.
if [ $(ls $cloudFWFile | grep -c "tar.gz") -eq 1 ]; then
    compressedFile=$cloudFWFile
    logger "Extracting the compressed firmware image file into '$WICIMAGEFILE'"
    mkdir -p $WICIMAGEFILE
    tar -xzf $cloudFWFile -C $WICIMAGEFILE && sync
    cloudFWFile=$(ls $WICIMAGEFILE/*.wic)
    if [ -z "$cloudFWFile" ]; then
        logger "Extracted firmware image file not found; cannot proceed, exiting."
        exit 1
    fi
    # Remove the uncompressed file for space saving.
    logger "Removing the compressed firmware image file '$compressedFile'"
    rm -rf $compressedFile && sync
fi

# Check if the cloudFWFile exists and then print its size
if [ -f $cloudFWFile ]; then
    fileSize=$(stat -c %s $cloudFWFile)
    logger "File '$cloudFWFile' exists and its size is '$fileSize' bytes."
else
    logger "File '$cloudFWFile' does not exist; cannot proceed, exiting."
    exit 1
fi

logger "Creating the directory '$EXTBLOCK'"
mkdir -p $EXTBLOCK

# Check if the /boot partition exists; if not, exit.
boot_partition=$(df | grep "/boot" | cut -d' ' -f1)
ota_boot_mount_point=$EXTBLOCK/ota_boot
ota_rootfs_mount_point=$EXTBLOCK/ota_rootfs
target_rootfs_mount_point=$EXTBLOCK/target_rootfs
old_boot_bkup=$EXTBLOCK/old_boot_bkup

if [ -z "$boot_partition" ]; then
    logger "No /boot partition found; cannot proceed, exiting."
    exit 1
fi

# check if $old_boot_bkup exists, delete it and create a new one
if [ -d $old_boot_bkup ]; then
    logger "Cleaning up the previous /boot partition back-up '$old_boot_bkup'"
    rm -rf $old_boot_bkup && sync
fi

mkdir -p $EXTBLOCK/{ota_boot,ota_rootfs,target_rootfs,old_boot_bkup}
if [ ! -d $ota_boot_mount_point ] || [ ! -d $old_boot_bkup ] || [ ! -d $ota_rootfs_mount_point ] || [ ! -d $target_rootfs_mount_point ]; then
    logger "Failed to create '$ota_boot_mount_point', '$ota_rootfs_mount_point', '$target_rootfs_mount_point' or '$old_boot_bkup'; cannot proceed."
    exit 1
fi

echo "boot_partition: $boot_partition"
echo "ota_boot_mount_point: $ota_boot_mount_point"
echo "old_boot_bkup: $old_boot_bkup"
echo "ota_rootfs_mount_point: $ota_rootfs_mount_point"
echo "target_rootfs_mount_point: $target_rootfs_mount_point"

# back-up the contents of /boot partition
logger "Backing up the contents of '/boot' partition to '$old_boot_bkup'"
cp -ar /boot/* $old_boot_bkup/ && sync
if [ $? -ne 0 ]; then
    logger "Failed to back-up the contents of '$ota_boot_mount_point' partition; cannot proceed, exiting."
    exit 1
else
    logger "The '/boot/' back-up to '$old_boot_bkup' is successful."
fi

ota_sector_info=$EXTBLOCK/sector.txt

[ -f $ota_sector_info ] && rm -f $ota_sector_info
if [ $(cat /version.txt | grep -c "dunfell") != "0" ]; then
    fdisk -l $cloudFWFile > $ota_sector_info
else
    fdisk -u -l $cloudFWFile > $ota_sector_info
fi

# Extract partition information from the WIC image; it only has 2 partitions /boot and /linuxRootFS.
BOOT_START_CHS=$(fdisk -l $cloudFWFile | grep -E "^$cloudFWFile"1 | awk '{print $4}')
FS_START_LBA=$(fdisk -l $cloudFWFile | grep -E "^$cloudFWFile"2 | awk '{print $4}')

# Convert CHS to LBA for the boot partition
IFS=',' read -r C H S <<< "$BOOT_START_CHS"
SECTORS_PER_TRACK=32
HEADS=4
CYLINDERS=$((C + 1))
BOOT_START_LBA=$(( (CYLINDERS * HEADS + H) * SECTORS_PER_TRACK + (S - 1) ))

# Calculate offsets in bytes (sector size is 512 bytes)
ota_boot_offset=$((BOOT_START_LBA * 512))
ota_rootfs_offset=$((FS_START_LBA * 512))

logger "Boot partition start CHS: $BOOT_START_CHS"
logger "Boot partition start LBA: $BOOT_START_LBA"
logger "RootFS partition start LBA: $FS_START_LBA"
logger "Boot partition offset: $ota_boot_offset"
logger "RootFS partition offset: $ota_rootfs_offset"

isRootFSUpdateSuccess=0
mount -o loop,offset=$ota_rootfs_offset -t ext4 $cloudFWFile $ota_rootfs_mount_point
if [ $? -ne 0 ]; then
    echo "Failed to mount $cloudFWFile at $ota_rootfs_mount_point with offset $ota_rootfs_offset"
    umount $BOOT_MOUNT_POINT
    exit 1
else
    # We have two rootfs partitions; one is the current rootfs and the other is the new rootfs.
    # identify the current rootfs partition and the new rootfs partition.
    activeBankDev=$(sed -e "s/.*root=//g" /proc/cmdline | cut -d ' ' -f1)
    if [ "$activeBankDev" == "/dev/mmcblk0p2" ]; then
        passiveBankDev="/dev/mmcblk0p3"
    else
        passiveBankDev="/dev/mmcblk0p2"
    fi
    logger "Active rootfs partition: $activeBankDev"
    logger "Passive partition: $passiveBankDev"
    mount -t ext4 $passiveBankDev $target_rootfs_mount_point
    if [ $? -ne 0 ]; then
        logger "Failed to mount the passive rootfs partition '$passiveBankDev'; cannot proceed, exiting."
        umount $ota_boot_mount_point
        umount $ota_rootfs_mount_point
        # TODO: roll-back everything
        exit 1
    else
        logger "Copying the contents of '$ota_rootfs_mount_point' to '$target_rootfs_mount_point'"
        rm -rf $target_rootfs_mount_point/* && sync
        cp -ar $ota_rootfs_mount_point/* $target_rootfs_mount_point/ && sync
        if [ $? -ne 0 ]; then
            logger "Failed to copy the contents of '$ota_rootfs_mount_point' to '$target_rootfs_mount_point'; revert to old
            and abort."
        else
            logger "The contents of '$ota_rootfs_mount_point' are copied to '$target_rootfs_mount_point' successfully."
            isRootFSUpdateSuccess=1
        fi
    fi
    umount $target_rootfs_mount_point
    umount $ota_boot_mount_point
    umount $ota_rootfs_mount_point
fi

isBootUpdateSuccess=0
# Mount the partitions using loopback with offset
mount -o loop,offset=$ota_boot_offset -t vfat $cloudFWFile $ota_boot_mount_point
if [ $? -ne 0 ]; then
    echo "Failed to mount $cloudFWFile at $ota_boot_mount_point with offset $ota_boot_offset"
    exit 1
else
    logger "Copying the contents of '$ota_boot_mount_point' to '/boot'"
    cp -ar $ota_boot_mount_point/* /boot/ && sync
    if [ $? -ne 0 ]; then
        logger "Failed to copy the contents of '$ota_boot_mount_point' to '/boot'; revert to old and abort."
        rm -rf /boot/* && sync && cp -ar $old_boot_bkup/* /boot/ && sync
        if [ $? -ne 0 ]; then
            logger "Failed to revert to old /boot partition; cannot proceed, exiting."
        else
            logger "Reverted '/boot' with contents of '$ota_boot_mount_point' successfully."
        fi
        umount $ota_boot_mount_point
        exit 1
    else
        logger "The contents of '$ota_boot_mount_point' are copied to '/boot' successfully."
        isBootUpdateSuccess=1
    fi
fi

if [ $isBootUpdateSuccess -eq 1 ] && [ $isRootFSUpdateSuccess -eq 1 ]; then
    # Both boot and rootfs partitions are updated successfully; update the cmdline.txt to use new RootFS partition.
    logger "Updating the cmdline.txt to use the new rootfs partition '$passiveBankDev'"
    sed -i "s|$activeBankDev|$passiveBankDev|g" /boot/cmdline.txt && sync
    if [ $? -ne 0 ]; then
        logger "Failed to update the cmdline.txt; manual recovery required, exiting."
        exit 1
    else
        logger "The cmdline.txt is updated successfully to use '$passiveBankDev'."
    fi
    reboot -f
else
    logger "The firmware update is failed; cannot proceed, exiting."
    exit 1
fi

exit 0
# reboot -f
