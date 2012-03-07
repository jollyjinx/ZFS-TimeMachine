
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



CheckBackup Script
-------------------

The checkbackup.perl script  checks if your backupscript is working correctly. As I do sleep my machine it will check if the snapshots are beeing done within the last 2*snapshotinterval+snapshottime seconds since the last wake or reboot. Exit code is correct depending if the snapshot is there or not.

It has three options:
	--pool which pool to use
	--snaphotinterval how often do you create snapshots
	--snapshotime how long it usually take for a snapshot to complete
	

	$[checkbackup.perl] module options are :
	--configurationfilename (string) default: config.ini
									 current: not used as Config:IniFiles module not present	
	--debug (number)                 default: 0	
	--help (option)                  default: 
									 current: 1	
	--pool (string)                  default: puddle	
	--snapshotinterval (number)      default: 300	
	--snapshottime (number)          default: 10



I'm currently using a script at crontab to tell me when things go wrong:
	
	#!/bin/zsh
	for pool in puddle "ocean/puddle"
	do
		./checkbackup.perl --pool="$pool" --snapshotinterval=300 || say -v alex "pool snapshot for $pool is too old"
	done

