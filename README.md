
ZFS TimeMachine
===============

Simple ZFS backup from one pool to another via sending snapshots, deleting old ones in time machine style. I'm using a Mac with TensCompliments ZFS implementation.


How it works
------------

- the script creates a snapshot on the source pool every time it is called.
- then it figures out the last snapshot on the destination pool that matches to one on the source pool.
- it sends the snapshot from the source to the destination.
- removes old snapshots on the source - it keeps just n-snapshots.
- removes old snapshots on the destination - time machine fashion : 5min/last day, 1 hour last week, 1 day last 3 months, 1 week thereafter


Requirements
------------
It requires perl and the Time::Local and Date::Parse libraries. If you are on a Mac you can install them by using the command line:

	$export PERL_MM_USE_DEFAULT=1 ; perl -MCPAN -e 'install Date::Parse' 'install Time::Local'

If you are on a different OS (like linux or bsd) everything should work. The checkbackupscript can't find out the last sleep and boot time then and will bug you about backups beeing too old when the machine has beeing powerd off for some time.

How to use
--------------

start the script from the command line with --sourcepool and --destinationpool options.

	$ zfstimemachinebackup.perl --help
	[zfstimemachinebackup.perl] module options are :
	--configurationfilename (string) default: config.ini
									 current: not used as Config:IniFiles module not present	
	--createdestinationsnapshotifneeded (flag) default: 1	
	--createsnapshotonsource (flag)  default: 0	
	--debug (number)                 default: 0	
	--destinationhost (string)       default: 	
	--destinationpool (string)       default: ocean/puddle	
	--help (option)                  default: 
									 current: 1	
	--replicate (flag)               default: 0	
	--snapshotstokeeponsource (number) default: 0	
	--sourcepool (string)            default: puddle


Set --recursive=1 if you want to send the pools and all sub pools recursively.

Set --createsnapshotonsource if you want to create snapshots on the source
Unset --createdestinationsnapshotifneeded=0 if you don't want the destinationpool to be created.


My current setup looks like this:

	$ zfs list
	puddle         181Gi  19.3Gi  175Gi  /Local
	ocean           708Gi  911Gi  371Ki  /Volumes/ocean
	ocean/puddle    167Gi  911Gi  163Gi  /Volumes/ocean/puddle

/Local is where my home directory lives. The script is called as follows
	
	$ ./zfstimemachinebackup.perl  --sourcepool=puddle --destinationpool=ocean/puddle --snapshotstokeeponsource=100 --createsnapshotonsource
	

So puddle is set as source, ocean/puddle will receive the snapshots from puddle and 100 snapshots are kept on puddle itself.

If you want to change the times when backups are removed on the destination you can change the following hash:

	my %buckets = 	(	1	*24*3600	=> 			5*60,	# last day every 5 minutes
						7	*24*3600 	=> 			3600,	# last 7 days, every hour
						90	*24*3600	=> 1	*24*3600,	# last 90 days, every day
					);

	my $buckettime = 7*24*3600; # keep weekly backups for beyond the time specified in %buckets.



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

It has three options :

	--pools which pool(s) to use comma separated list
	--snaphotinterval how often do you create snapshots
	--snapshotime how long it usually take for a snapshot to complete
	

	$[checkbackup.perl] module options are :
	--configurationfilename (string) default: config.ini
									 current: not used as Config:IniFiles module not present	
	--debug (number)                 default: 0	
	--help (option)                  default: 
									 current: 1	
	--pools (string)                 default: puddle	
	--snapshotinterval (number)      default: 300	
	--snapshottime (number)          default: 10



I'm currently using a script at crontab to tell me when things go wrong:
	
	#!/bin/zsh

	./checkbackup.perl --pools="puddle/jolly,puddle/jolly/Pictures,puddle/jolly/Library" --snapshotinterval=7200 || say -v alex "pool snapshot for $pool is too old"
	./checkbackup.perl --pools="example.com:rootpool/puddle/jolly/Pictures" --snapshotinterval=7200 || say -v alex "pool snapshot for $pool is too old"



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


