# Western Digital - MyBook Live

An attempt to make it easy to debrick, and possibly manage, a WD *MyBook Live* NAS.

Pretty much everything comes from various online sources which may not be there forever, hence this repository.

## Notes

The script is intended to be executed as `root`.

-----

So far, I have only tested – with success – the `os-recovery` command. Right now its `--help` is quite poor, have a look at the source.

-----

In order to restore the OS, you have to retrieve the `apnc-xxxxxx-zzz-yyyymmdd.deb` firmware's file. The script wants the `*.img` archived inside.
Note to self: I have several such files on an external hard disk.

I suggest to restore a previous version and then upgrade to the last one with the NAS interface (should we miss something not mandatory in the process).

-----

There are some utilities and useful informations (as comments) inside the script; e.g. for retrieve files from the *DataVolume* when partially-bricked and mounted to another host machine (hint: it uses `debugfs`).

-----

I used a spare Ubuntu virtual-machine to perform the debrick process; I don't remember, but I suppose that I may have needed to perform the following commands:

	sudo apt-get update
	sudo apt install gddrescue
	sudo apt-get install mdadm
	sudo apt install gcc
	sudo apt install smartmontool
	sudo apt install pv

-----

If the NAS is partially working, before running the script it may be necessary to stop the RAID array:

	sudo mdadm --manage --stop /dev/md0 -f

-----

In case of new disk with bad sectors, the following may be useful:

	# maybe try with also the `-y` flag
	sudo ddrescue /dev/zero /dev/sdb -f -D -v
	sudo dd if=/dev/zero bs=1M | pv -p -e -r -s 2T | sudo dd of=/dev/sdb bs=1M
	# Prints the SMART information about the disk:
	smartctl -a /dev/sdb
