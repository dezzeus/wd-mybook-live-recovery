#!/usr/bin/env bash

###
### mybooklive -- a recovery utility
###
### Usage:
###   mybooklive <command> [[<sub_command>] [<parameters>]]

main() {
    # There should be at least one parameter:
    [[ $# -gt 0 ]] || { display_help; exit -1; }
    #check that requirements are fullfilled
    #[[ "$(id -u)" != "0" ]] || bad_msg "This script must be run as root."
    # Handle the command:
    handle_command "$@"
}

display_help() {
    which awk &> /dev/null || bad_msg "Cannot use awk; please install it."
    # [TBD]: use different prefixes in order to choose what to show (also given by the context)
    awk -F '### ' '/^###/ { print $2 }' "$0"
}

###
### Commands:
###   help | -h | --help        Show this message.
###   os-recovery               Format and install only the OS.
handle_command() {
    case $1 in
        *help|"-h")    display_help                   ;;
        "disk-init")   init_disk "${@:2}"             ;;
        "fresh")       fresh_install "${@:2}"         ;;
        "os-recovery") attempt_os_recovery "${@:2}"   ;;
        "extract-deb") extract_deb_file "${@:2}"      ;;
        *)             bad_msg "Command not defined." ;;
    esac
}

#---[ COMMANDS ]---------------------------------------------------------------

init_disk() {
    if [ $# -gt 0 ]; then
        set_disk "$1" "$2"
    fi
    which mdadm &> /dev/null || bad_msg "Cannot use mdadm; please install it."
    which parted &> /dev/null || bad_msg "Cannot use parted; please install it."

    # [TBD]: stop RAID if exists ?
    fn_wipe_previous_partitioning_data
    fn_make_partitions
}

fresh_install() {
    which mdadm &> /dev/null || bad_msg "Cannot use mdadm; please install it."
    which gcc &> /dev/null || bad_msg "Cannot use gcc; please install it."
    which pv &> /dev/null || bad_msg "Cannot use pv; please install it."

    # make sure dev/md0 is not mounted or in use:
    # mdadm --stop /dev/md0
    # mdadm --remove /dev/md0

    set_disk "$1" "$3"

    # [TBD]: stop RAID if exists ?
    init_disk
    # create the swap partition
    echo "Creating the swap partition..."
    mkswap "$swapDevice"
    sync
    sleep 2

    fn_raid_prepare
    fn_install_os "$2"
    fn_raid_start_mirroring
    fn_fix_endianess

    fn_prepare_data_volume

    echo "Done."
    echo "You can now re-assemble the WD MyBook Live NAS drive."
    echo
    echo "Once inside, do:"
    echo "  mkswap /dev/sda3"
    echo "  reboot"
}

attempt_os_recovery() {
    which mdadm &> /dev/null || bad_msg "Cannot use mdadm; please install it."
    which gcc &> /dev/null || bad_msg "Cannot use gcc; please install it."
    which pv &> /dev/null || bad_msg "Cannot use pv; please install it."

    set_disk "$1" "$3"

    # [TBD]: stop RAID if exists ?
    fn_wipe_only_os_partitions
    fn_raid_prepare
    fn_install_os "$2"
    fn_raid_start_mirroring
    fn_fix_endianess

    echo "Done."
    echo "You can now re-assemble the WD MyBook Live NAS drive."
    echo
    echo "Once inside, do:"
    echo "  mkswap /dev/sda3"
    echo "  reboot"
}

apt_post_recovery() {
    # The latest firmware use Debian 7 "wheezy" and should support Debian 6 "squeeze"
    # The provided repositories doesn't support those versions anymore, hence we need to add extra ones.
    # You can use repositories over HTTPS if the according mirror supports it, but versions of Debian
    # before the 9 "stretch", will need to install the apt-transport-https package first.
    echo "deb http://debian.ethz.ch/debian-archive/ wheezy main contrib non-free" >> /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian/ wheezy main contrib non-free" >> /etc/apt/sources.list
    echo "deb http://debian.ethz.ch/debian-archive/ squeeze main contrib non-free" >> /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian/ squeeze main contrib non-free" >> /etc/apt/sources.list
    apt-get update &> /dev/null
}

install_compile_tools() {
    apt-get update &> /dev/null
    cd /tmp
    # Due to un-verified repositories, we need to pass `-y --force-yes`.
    # Due to libc being shipped also by WD, we need to tell dpkg to overwrite that.
    apt-get -o Dpkg::Options::="--force-overwrite" --force-yes -y install gcc
    # the upgrade of libc will ask (ncurses UI) to restart some services; this is fine.
    apt-get -y --force-yes install make
}

# DO NOT RUN AS A COMMAND; do step by step or automate it! Right now is for documentation only!
install_minidlna() {
    # ensure that the stock DLNA service is stopped.
    # [ToDo]: automate it!
    apt-get update &> /dev/null
    # check if install_compile_tools is needed
    cd /tmp
    # MiniDLNA's README list the followings prerequisites:
    # libexif, libjpeg, libid3tag, libFLAC, libvorbis, libsqlite3, libavformat (the ffmpeg libraries)
    apt-get -y --force-yes --no-install-recommends install libexif-dev libjpeg8-dev libid3tag* libFLAC-dev libvorbis-dev libsqlite3-dev libavformat-dev
    # The configure script seems to check also for:
    # libavutil, libavcodec, libogg; avahi-client, avahi-common
    # Avahi, an implementation of DNS Service Discovery (DNS-SD RFC 6763) over Multicast DNS (mDNS RFC 6762) compatible with Apple Bonjour, is probably not needed.
    apt-get -y --force-yes --no-install-recommends install libavutil-dev libavcodec-dev libogg-dev
    # Suggested from blogs:
    apt-get -y --force-yes --no-install-recommends install ffmpeg imagemagick mediainfo ffmpegthumbnailer libfreetype6-dev libass-dev
    #apt-get install mencoder transcode libmp3lame-dev libx264-dev libva-dev libvpx-dev libvo-aacenc-dev libv4l-dev

    # wget's SSL cannot download over HTTPS.
    #wget http://sourceforge.net/projects/minidlna/files/latest/download?source=files -O minidlna.tar.gz
    cp /DataVolume/shares/Public/Software/minidlna-1.3.0.tar.gz minidlna.tar.gz
    tar -xvf minidlna.tar.gz
    # [TBD]: chmod -R 777 ?
    cd minidlna*
    # Configure, compile and install miniDLNA, it will take 5 minutes:
    # [NOTE]: disable multi-language (nls) because I cannot install gettext.
    ./configure --disable-nls && make && make install
    # Copy the miniDLNA default configuration file
    cp minidlna.conf /etc/
    # replace the followings in the config file:
    # media_dir=AVP,/DataVolume/shares/Public
    # friendly_name=MyBook Live
    # log_dir=/var/log
    # log_level=general,artwork,database,inotify,scanner,metadata,http,ssdp,tivo=error
    # wide_links=yes
    # enable_subtitles=yes
    # root_container=B
    # Copy the miniDLNA init.d script to autostart miniDLNA on boot:
    cp linux/minidlna.init.d.script /etc/init.d/minidlna
    chmod +x /etc/init.d/minidlna
    # Update rc to use the miniDLNA defaults:
    update-rc.d minidlna defaults
    /usr/local/sbin/minidlnad -R
    # https://www.htpcguides.com/install-latest-readymedia-minidlna-ubuntu/
    # https://terminal28.com/minidlna-upnp-media-server-debian-linux/
    # https://community.wd.com/t/breathing-new-life-into-mbl-new-disk-sleep-monitoring-minidlna-openvpn/161764/4
    # delete stuff from /tmp ?
}

#---[ FUNCTIONS ]---------------------------------------------------------------

# clear any old partitioning data, etc.
fn_wipe_previous_partitioning_data() {
    if [ -e "${targetDisk}1" ]; then
        dd if=/dev/zero of=${targetDisk}1 bs=1M count=32
    fi
    if [ -e "${targetDisk}2" ]; then
        dd if=/dev/zero of=${targetDisk}2 bs=1M count=32
    fi
    if [ -e "${targetDisk}3" ]; then
        dd if=/dev/zero of=${targetDisk}3 bs=1M count=32
    fi
    if [ -e "${targetDisk}4" ]; then
        dd if=/dev/zero of=${targetDisk}4 bs=1M count=32
    fi

    if [ -e "${targetDisk}" ]; then
        # badblocks is used to search for bad blocks on a device (usually a disk partition).
        # usage:    badblocks [options] <device> [<last_block>] [<first_block>]
        #   device is the special file corresponding to the device (e.g /dev/hdc1).
        #   last-block is the last block to be checked; if it is not specified, the last block on the device is used as a default.
        #   first-block is an optional parameter specifying the starting block number for the test, which allows the testing to start in the middle of the disk. If it is not specified the first block on the disk is used as a default.
        # options:
        # -s    Show the progress.
        #       Note that badblocks may do multiple test passes over the disk.
        # -w    Use write-mode test.
        # -f    Perform a destructive test on a device.
        #       This can potentially crash and/or damage the filesystem.
        # -b    Specify the size of blocks in bytes.
        #       1 MiB = 1048576 B
        # -t    Specify a test pattern to be read and written to disk blocks.
        backgroundPattern=0xE5
        # Maybe it was 16 blocks due to the 16M space in the partition scheme
        badblocks -swf -b 1048576 -t ${backgroundPattern} ${targetDisk} 16 0
    fi
    sync
    sleep 2

    unset backgroundPattern
}

fn_make_partitions() {
    # [NOTE]: must match the set_disk function below!
    #  - 2048M  (2576 -  528)   device 1
    #  - 2048M  (4624 - 2576)   device 2
    #  - 512M   ( 528 -   16)   device 3
    #  - *      (4624 - ....)   device 4
    # use a 'here document' to allow parted to understand the -1M
    partitionScheme="$(cat <<- MBL_PARTITION_SCHEME
        mklabel gpt
        mkpart primary 528M  2576M
        mkpart primary 2576M 4624M
        mkpart primary 16M 528M
        mkpart primary 4624M -1M
        set 1 raid on
        set 2 raid on
        quit
MBL_PARTITION_SCHEME
    )"
    parted "$targetDisk" --align optimal "$partitionScheme"
    sync
    sleep 1

    parted "$targetDisk" print

    unset partitionScheme
}

fn_wipe_only_os_partitions() {
    if [ -e "${raidBlockDisk1}" ]; then
        dd if=/dev/zero of=${raidBlockDisk1} bs=1M count=32
    fi
    if [ -e "${raidBlockDisk2}" ]; then
        dd if=/dev/zero of=${raidBlockDisk2} bs=1M count=32
    fi
    if [ -e "${swapDevice}" ]; then
        dd if=/dev/zero of=${swapDevice} bs=1M count=32
    fi
}

fn_raid_prepare() {
    # MBL default metadataVersion seems to be 0.9 (script) / 0.90 (man page)
    # [NOTE]: using 1.2 doesn't allow the OS to be installed due to insufficient space.
    metadataVersion="0.9"

    echo "Clearing old superblock data on the RAID disks..."
    mdadm --zero-superblock --force --verbose ${raidBlockDisk1} > /dev/null
    sleep 1
    mdadm --zero-superblock --force --verbose ${raidBlockDisk2} > /dev/null
    sync
    sleep 1

    # Create a RAID-1 two-device with just the first block disk active.
    # --run Insist that mdadm run the array, even if some of the components appear to be active in another array or filesystem.
    # Give the word "missing" in place of a device name; this will cause mdadm to leave the corresponding slot in the array empty.
    mdadm --create ${raidDevice} --verbose --metadata="$metadataVersion" --raid-devices=2 --level=raid1 --run ${raidBlockDisk1} missing
    mdadm --wait ${raidDevice}
    sync
    sleep 2
}

fn_raid_start_mirroring() {
    # add the second partition to the raid mirror
    echo "Adding the second partition to the RAID mirror..."
    mdadm ${raidDevice} --add --verbose ${raidBlockDisk2}
    sleep 1
    echo "- Please wait for RAID RE-SYNC to complete..."
    mdadm --wait ${raidDevice}
    echo "- RAID Done."
    sync
    sleep 1

    #mdadm --detail ${raidDevice}
}

fn_install_os() {
    rootFileSystemImage="$1"
    rootFileSystemMountPoint="/mnt/WDroot"

    echo "OS installation:"

    echo "- Initialization of a journaled ext3 file-system..."
    # Format the RAID-mirrored device with a journaled ext3 file-system:
    # -b    Specify the size of blocks in bytes.
    # -c    Check the device for bad blocks before creating the file system. If this option is specified twice, then a slower read-write test is used instead of a fast read-only test.
    mkfs.ext3 -c -c -b 4096 ${raidDevice}
    sync
    sleep 2

    echo "- Copying the root filesystem to the target disk..."
    dd if=${rootFileSystemImage} bs=1M | pv -p -e -r -s 2T | dd of=${raidDevice} bs=1M

    echo "- Mounting filesystem..."
    # Mount filesystem
    mkdir -p "${rootFileSystemMountPoint}"
    mount ${raidDevice} "${rootFileSystemMountPoint}"
    echo "--- Setting up the bootloader..."
    # Copy uboot script too boot directory
    cp "${rootFileSystemMountPoint}/usr/local/share/bootmd0.scr" "${rootFileSystemMountPoint}/boot/boot.scr"
    sync
    sleep 2
    echo "--- Enabling SSH..."
    # Enable SSH:	[user: root]	[psw: welc0me]
    echo "enabled" > "${rootFileSystemMountPoint}/etc/nas/service_startup/ssh"

    ## ensures reboot
    #echo no     > "${rootFileSystemMountPoint}/sys/class/leds/a3g_led/blink"
    #echo yellow > "${rootFileSystemMountPoint}/sys/class/leds/a3g_led/color"
    sync
    sleep 1

    echo "- Un-mounting filesystem..."
    umount "${rootFileSystemMountPoint}"
    rm -R "${rootFileSystemMountPoint}"

    unset rootFileSystemMountPoint
}

fn_fix_endianess() {
    echo "Fix: (x86[_64]) BigEndian architecture --> (PPC) LittleEndian architecture"
    provide_endianess_swapper
    echo "- Stopping the RAID array..."
    mdadm --stop ${raidDevice}
    echo "- Please wait..."
    ./swap ${raidBlockDisk1}
    ./swap ${raidBlockDisk2}
    sleep 1
    sync
    rm ./swap
    # [TBD]: re-run the RAID array ?
}

fn_prepare_data_volume() {
    dataVolumeMountPoint="/mnt/WDdata"

    # format the data volume file system
    # if outputs a warning about blocksize 65536, proceed anyway
    # -m    Specify the percentage of the filesystem blocks reserved for the super-user.
    #       The default percentage is 5%.
    #mkfs.ext4 -b 65536 -m 0 ${dataVolumeDevice}
    mkfs.ext4 -O extent,has_journal -b 65536 -m 0 ${dataVolumeDevice}
    
    sync
    sleep 2

    # Mount filesystem
    mkdir -p "${dataVolumeMountPoint}"
    # [TBD]: use -sb to specify a different superblock (Linux version 2.0.* changed behaviour, so it may be necessary); see man page.
    #mount -t ext4 -o noatime,nodelalloc $dataVolumeDevice "${dataVolumeMountPoint}"
    mount -t ext4 -o noatime,nodiratime,auto_da_alloc $dataVolumeDevice "${dataVolumeMountPoint}"

    mkdir -p "${dataVolumeMountPoint}/DataVolume/cache"

    mkdir -p "${dataVolumeMountPoint}/DataVolume/shares/Public/Shared Music"
    mkdir -p "${dataVolumeMountPoint}/DataVolume/shares/Public/Shared Videos"
    mkdir -p "${dataVolumeMountPoint}/DataVolume/shares/Public/Shared Pictures"
    mkdir -p "${dataVolumeMountPoint}/DataVolume/shares/Public/Software"

    chmod -R 755 "${dataVolumeMountPoint}/DataVolume/shares"
    chgrp -R share "${dataVolumeMountPoint}/DataVolume/shares"

    # create hidden backup shares
    mkdir -p "${dataVolumeMountPoint}/DataVolume/backup/SmartWare"
    mkdir -p "${dataVolumeMountPoint}/DataVolume/backup/TimeMachine"
    chmod -R 755 "${dataVolumeMountPoint}/DataVolume/backup"
    chgrp -R share "${dataVolumeMountPoint}/DataVolume/backup"

    sync
    sleep 1

    umount ${dataVolumeMountPoint}
    rm -R ${dataVolumeMountPoint}

    unset dataVolumeMountPoint
}

fn_update_firmware() {
    debFilePath="$1" # e.g.: /DataVolume/shares/Public/apnc-021009-124-20111113.deb
    /usr/local/sbin/updateFirmwareFromFile.sh "$debFilePath"
    # no output is shown, you need to wait for the MBL to automatically reboot.
    #
    # copy the firmware into /CacheVolume and then rename to updateFile.deb
    # updateFirmwareFromFile.sh /CacheVolume/updateFile.deb
    # reboot
}

#---[ UTIITIES ]---------------------------------------------------------------

bad_msg() {
	echo "$1" >&2
	exit -1
}

set_disk() {
    targetDisk="${1:-/dev/sdb}"
    raidDevice="${2:-/dev/md0}"
    raidBlockDisk1="${targetDisk}1"
    raidBlockDisk2="${targetDisk}2"
    swapDevice="${targetDisk}3"
    dataVolumeDevice="${targetDisk}4"
}

show_smart_info() {
    if [ $# -gt 0 ]; then
        set_disk "$1"
    fi
    which smartctl &> /dev/null || bad_msg "Cannot use smartctl; please install smartmontool."
    smartctl -a "$targetDisk"
}

locate_disk() {
    # Find which dev is your usb hdd from MBL:
    #sudo fdisk -l

    disk=notset
    for x in {a..z}
    do
        # avoid a to literal matching in order to avoid incompability.
        if [ -e /dev/sd${x} ]; then
            if [ ! -e /dev/sd${x}0 -a ! -e /dev/sd${x}5 ]; then
                diskTest=$(parted --script /dev/sd${x} print)
                #if [[ $diskTest = *WD??EARS* ]]; then
                if [[ $diskTest = *WD??E?RS* ]]; then
                    if [[ $diskTest = *??00GB* ]]; then
                        if [[ $diskTest = *3*B*B*5??MB*primary* ]]; then
                            if [[ $diskTest = *1*B*B*2???MB*ext3*primary*raid* ]]; then
                                if [[ $diskTest = *2*B*B*2???MB*ext3*primary*raid* ]]; then
                                    if [[ $diskTest = *4*B*B*GB*ext4*primary* ]]; then
                                        if [ $disk != notset ]; then
                                            bad_msg "Multiple disk founds, you must enter it manually."
                                        fi
                                        disk=/dev/sd${x}
                                    fi;
                                fi;
                            fi;
                        fi;
                    fi;
                fi;
            fi;
        fi
    done
    if [ $disk == notset ]; then
        bad_msg "Cannot find the disk."
    fi
    echo "$disk"
}

provide_endianess_swapper() {
    #construct the swap program
    echo "\
    #include <unistd.h>
    #include <stdlib.h>
    #include <fcntl.h>
    #include <stdio.h>
    #include <sys/mount.h>

    #define MD_RESERVED_BYTES      (64 * 1024)
    #define MD_RESERVED_SECTORS    (MD_RESERVED_BYTES / 512)

    #define MD_NEW_SIZE_SECTORS(x) ((x & ~(MD_RESERVED_SECTORS - 1)) - MD_RESERVED_SECTORS)

    main(int argc, char *argv[])
    {
        int fd, i;
        unsigned long size;
        unsigned long long offset;
        char super[4096];
        if (argc != 2) {
            fprintf(stderr, \"Usage: swap_super device\\n\");
            exit(1);
        }
        fd = open(argv[1], O_RDWR);
        if (fd<0) {
            perror(argv[1]);
            exit(1);
        }
        if (ioctl(fd, BLKGETSIZE, &size)) {
            perror(\"BLKGETSIZE\");
            exit(1);
        }
        offset = MD_NEW_SIZE_SECTORS(size) * 512LL;
        if (lseek64(fd, offset, 0) < 0LL) {
            perror(\"lseek64\");
            exit(1);
        }
        if (read(fd, super, 4096) != 4096) {
            perror(\"read\");
            exit(1);
        }

        for (i=0; i < 4096 ; i+=4) {
            char t = super[i];
            super[i] = super[i+3];
            super[i+3] = t;
            t=super[i+1];
            super[i+1]=super[i+2];
            super[i+2]=t;
        }
        /* swap the u64 events counters */
        for (i=0; i<4; i++) {
            /* events_hi and events_lo */
            char t=super[32*4+7*4 +i];
            super[32*4+7*4 +i] = super[32*4+8*4 +i];
            super[32*4+8*4 +i] = t;

            /* cp_events_hi and cp_events_lo */
            t=super[32*4+9*4 +i];
            super[32*4+9*4 +i] = super[32*4+10*4 +i];
            super[32*4+10*4 +i] = t;
        }

        if (lseek64(fd, offset, 0) < 0LL) {
            perror(\"lseek64\");
            exit(1);
        }
        if (write(fd, super, 4096) != 4096) {
            perror(\"write\");
            exit(1);
        }
        exit(0);

    }" > ./swap.c

    echo "- Compiling swap.c..."
    gcc swap.c -o swap
    rm swap.c
}

extract_deb_file() {
    debFile="$1"
    destFolder="${2:-.}/mbl_firmware"
    [ -d "$destFolder" ] || mkdir -p "$destFolder"
    ar p "$debFile" data.tar.lzma | unlzma | tar -x -C "$destFolder"
    [ $? = 0 ] || bad_msg "deb file extraction encountered problems."
}

# [TBD]: expand $PATH
#PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
#export PATH=$PATH:/opt/bin:/opt/sbin:/bin:/sbin

#------------------------------------------------------------------------------

main "$@"

# Per accedere ai dati su x86:
# The debugfs program is an interactive file system debugger.
# see: https://linux.die.net/man/8/debugfs
#	sudo debugfs
#
#	open -b 65536 ${disk}4
#	cd /shares/Public
#	ls // Press Q to exit the listing
#	rdump "<NAS_folder>" <backup_folder>

# FAQ: https://support-en.wd.com/app/answers/detail/a_id/23416/kw/My%20Book%20Live
# Other: https://github.com/MyBookLive

# On Windows: http://mybooklive/
# On Mac: http://mybooklive.local/

# sudo e2fsck -b block_number /dev/xxx