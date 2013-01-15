ZFS TimeMachine
===============

Simple ZFS backup from one pool to another via sending snapshots, deleting old ones in time machine style. I'm using a Mac with TensCompliments ZFS implementation on my Mac and Mac and FreeBSD as destination hosts.


How it works
------------

- the script creates a snapshot on the source dataset every time it is called.
- then it figures out the last snapshot on the destination dataset that matches to one on the source dataset.
- it sends the snapshot from the source to the destination.
- removes old snapshots on the source - it keeps just n-snapshots.
- removes old snapshots on the destination - time machine fashion : 5min/last day, 1 hour last week, 1 day last 3 months, 1 week thereafter


Requirements
------------
It requires perl and the Time::Local and Date::Parse libraries. If you are on a Mac you can install them by using the command line:

	$export PERL_MM_USE_DEFAULT=1 ; perl -MCPAN -e 'install Date::Parse' 'install Time::Local'

If you are on a different OS (like linux or bsd) everything should work.

How to use
--------------

start the script from the command line with --sourcedataset and --destinationdataset options.

	$ zfstimemachinebackup.perl --help
	[zfstimemachinebackup.perl] module options are :
	--configurationfilename (string) default: config.ini
									 current: not used as Config:IniFiles module not present	
	--createdestinationsnapshotifneeded (flag) default: 1	
	--createsnapshotonsource (flag)  default: 0	
	--debug (number)                 default: 0	
	--destinationhost (string)       default: 	
	--destinationdataset (string)    default: ocean/puddle	
	--help (option)                  default: 
									 current: 1	
	--replicate (flag)               default: 0	
	--snapshotstokeeponsource (number) default: 0	
	--sourcedataset (string)            default: puddle

	--keepbackupshash (string)       default: 24h=>5min,7d=>1h,90d=>1d,1y=>1w,10y=>1month	
	--maximumtimeperfilesystemhash (string) default: .*=>10yrs,.+/(Dropbox|Downloads|Caches|Mail Downloads|Saved Application State|Logs)$=>1month	
	--recursive (flag)               default: 0	


Set --recursive if you want to send the datasets and all sub datasets recursively.
Set --createsnapshotonsource if you want to create snapshots on the source.
Unset --createdestinationsnapshotifneeded=0 if you don't want the destinationdataset to be created.


My current setup looks like this:

	$ zfs list
	puddle                                                           207Gi   214Gi   864Ki  /Volumes/puddle
	puddle/Local                                                     207Gi   214Gi  2.50Gi  /Local
	puddle/Local/Users                                               204Gi   214Gi   891Mi  /Local/Users
	puddle/Local/Users/jolly                                         204Gi   214Gi  50.4Gi  /Local/Users/jolly
	puddle/Local/Users/jolly/Disks                                  22.4Gi   214Gi  22.3Gi  /Local/Users/jolly/Disks
	puddle/Local/Users/jolly/Downloads                              1.62Gi   214Gi  1.62Gi  /Local/Users/jolly/Downloads
	puddle/Local/Users/jolly/Dropbox                                3.53Gi   214Gi  3.53Gi  /Local/Users/jolly/Dropbox
	puddle/Local/Users/jolly/Library                                44.6Gi   214Gi  28.3Gi  /Local/Users/jolly/Library
	puddle/Local/Users/jolly/Library/Caches                         2.05Gi   214Gi  2.04Gi  /Local/Users/jolly/Library/Caches
	puddle/Local/Users/jolly/Library/Logs                           72.2Mi   214Gi  70.4Mi  /Local/Users/jolly/Library/Logs
	puddle/Local/Users/jolly/Library/Mail                           13.8Gi   214Gi  13.7Gi  /Local/Users/jolly/Library/Mail
	puddle/Local/Users/jolly/Library/Mail Downloads                  868Ki   214Gi   868Ki  /Local/Users/jolly/Library/Mail Downloads
	puddle/Local/Users/jolly/Library/Saved Application State        50.8Mi   214Gi  9.38Mi  /Local/Users/jolly/Library/Saved Application State
	puddle/Local/Users/jolly/Pictures                               80.4Gi   214Gi  80.4Gi  /Local/Users/jolly/Pictures
	ocean                                                           1.24Ti   567Gi   266Ki  /Volumes/ocean
	ocean/puddle                                                     635Gi   567Gi   187Ki  /Volumes/ocean/puddle
	ocean/puddle/Local                                               635Gi   567Gi  1.76Gi  /Volumes/ocean/puddle/Local
	ocean/puddle/Local/Users                                         632Gi   567Gi   539Mi  /Volumes/ocean/puddle/Local/Users
	ocean/puddle/Local/Users/jolly                                   631Gi   567Gi  49.8Gi  /Volumes/ocean/puddle/Local/Users/jolly
	ocean/puddle/Local/Users/jolly/Disks                            48.0Gi   567Gi  22.1Gi  /Volumes/ocean/puddle/Local/Users/jolly/Disks
	ocean/puddle/Local/Users/jolly/Downloads                        1.62Gi   567Gi  1.62Gi  /Volumes/ocean/puddle/Local/Users/jolly/Downloads
	ocean/puddle/Local/Users/jolly/Dropbox                          4.42Gi   567Gi  3.47Gi  /Volumes/ocean/puddle/Local/Users/jolly/Dropbox
	ocean/puddle/Local/Users/jolly/Library                          93.7Gi   567Gi  22.6Gi  /Volumes/ocean/puddle/Local/Users/jolly/Library
	ocean/puddle/Local/Users/jolly/Library/Caches                   1.90Gi   567Gi  1.90Gi  /Volumes/ocean/puddle/Local/Users/jolly/Library/Caches
	ocean/puddle/Local/Users/jolly/Library/Logs                     65.2Mi   567Gi  65.1Mi  /Volumes/ocean/puddle/Local/Users/jolly/Library/Logs
	ocean/puddle/Local/Users/jolly/Library/Mail                     18.6Gi   567Gi  11.2Gi  /Volumes/ocean/puddle/Local/Users/jolly/Library/Mail
	ocean/puddle/Local/Users/jolly/Library/Mail Downloads            210Ki   567Gi   208Ki  /Volumes/ocean/puddle/Local/Users/jolly/Library/Mail Downloads
	ocean/puddle/Local/Users/jolly/Library/Saved Application State  12.4Mi   567Gi  5.83Mi  /Volumes/ocean/puddle/Local/Users/jolly/Library/Saved Application State
	ocean/puddle/Local/Users/jolly/Pictures                         85.7Gi   567Gi  73.8Gi  /Volumes/ocean/puddle/Local/Users/jolly/Pictures

/Local is where my home directory lives. The script is called as follows
	

	$ ./zfstimemachinebackup.perl  --sourcedataset=puddle --destinationdataset=ocean/puddle --snapshotstokeeponsource=100 --createsnapshotonsource --recursive
	
So puddle is set as source, ocean/puddle will receive the snapshots from puddle and 100 snapshots are kept on puddle itself.

I'm also sending backups from the backupdisk to a remote machine with less space, so I keep backups only for 3 months:

	$ ./zfstimemachinebackup.perl  --sourcedataset=ocean/puddle --destinationdataset=backups/puddle --destinationhost=server.example.com --recursive --maximumtimeperfilesystemhash='.*=>3months,.+/(Dropbox|Downloads|Caches|Mail Downloads|Saved Application State|Logs)$=>1month'



If you want to change the times when backups are removed on the destination you can change keepbackupshash commandline hash. The default means:

	24h=>5mi	for snapshots younger than keep not more than one per 5 minutes
	7d=>1h		for snapshots younger than 7 days keep not more than one snapshot per 1 hour
	.
	.
	.

Currently I do have some special directories that are not kept as long as I do not mind loosing history in them. Those are defined via the maximumtimeperfilesystemhash.

	.*=>10yrs	keep everything 10 years by default - after that snapshots are removed
	
	.+/(Dropbox|Downloads|Caches|Mail Downloads|Saved Application State|Logs)$=>1month
				remove snapshots older than one month for directories ending with the regex.
	


Autoscrub script
----------------
For some reason the autoscrub feature of tens complement does not work for me, so I added a script you can use to my ZFS Timemachine script.

	usage: ./autoscrub.perl --scrubinterval=14

will scrub your pools every 14 days. If you cancel a scrub that will be recognized but also it will be scrubed after the scrubinterval passed , in case you forgot that you canceled it.

You can start it for different pools as well.

I'm using it in a crontab entry: 
	1 * * * * cd ~jolly/Binaries/ZFSTimeMachine;./autoscrub.perl >/dev/null 2>&1



CheckBackup Script
-------------------

The checkbackup.perl script  checks if your backupscript is working correctly. As I do sleep my machine it will check if the snapshots are beeing done within the last 2*snapshotinterval+snapshottime seconds since the last wake or reboot. Exit code is correct depending if the snapshot is there or not.
If the checkbackupscript can't find out the last sleep and boot time it will bug you about backups beeing too old when the machine has beeing powerd off for some time.

It has three options :

	--datasets which dataset(s) to use comma separated list
	--snaphotinterval how often do you create snapshots
	--snapshotime how long it usually take for a snapshot to complete
	

	$[checkbackup.perl] module options are :
	--configurationfilename (string) default: config.ini
									 current: not used as Config:IniFiles module not present	
	--debug (number)                 default: 0	
	--help (option)                  default: 
									 current: 1	
	--datasets (string)              default: puddle	
	--snapshotinterval (number)      default: 300	
	--snapshottime (number)          default: 10


I'm currently using a script at crontab to tell me when things go wrong:
	
	#!/bin/zsh

	./checkbackup.perl --datasets="puddle/Local,puddle/Local/Users,puddle/Local/Users/jolly,puddle/Local/Users/jolly/Library,puddle/Local/Users/jolly/Disks,puddle/Local/Users/jolly/Pictures" --snapshotinterval=7200 || say -v alex "dataset snapshot on local host is too old"
	./checkbackup.perl --datasets="example.com:pond/puddle/Local,example.com:pond/puddle/Local/Users,example.com:pond/puddle/Local/Users/jolly,example.com:pond/puddle/Local/Users/jolly/Library,example.com:pond/puddle/Local/Users/jolly/Disks,example.com:pond/puddle/Local/Users/jolly/Pictures" --snapshotinterval=7200 || say -v alex "dataset pond snapshots on example.com are too old"



TimeMachine backups to ZFS Volumes
----------------------------------
I now have moved everything except for my boot partitions to ZFS. To have some backup of the root drive I'm backing that of with Apples provided TimeMachine and here is how I do it:

Create a zfs filesystem for the TimeMachine backups for several machines:

	zfs create ocean/TimeMachine


Create a 100Gb sparsebundle for TimeMachine (my root is rather small, your mileage may vary):

	hdiutil create -size 100g -library SPUD -fs JHFSX -type SPARSEBUNDLE -volname "tmmachinename" /Volumes/ocean/TimeMachine/tmmachinename.sparsebundle


Set up crontab to mount the sparsebundle every 20 minutes if it's not mounted yet. This is needed as TimeMachine will unmount the backup disk if it's a sparsebundle after backing up.

	*/20 * * * *	if [ ! -d /Volumes/tmtinkerbell ] ;then hdiutil attach /Volumes/ocean/TimeMachine/tmmachinename.sparsebundle; fi </dev/null >/dev/null 2>&1


Set up TimeMachine to use the sparsebundle:

	tmutil setdestination -p /Volumes/tmmachinename


