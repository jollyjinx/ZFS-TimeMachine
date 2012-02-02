
ZFS TimeMachine
===============

Simple ZFS backup from one pool to another via sending snapshots, deleting old ones in time machine style. I'm unsing a Mac with TensCompliments ZFS implementation.


How it works
------------

- the script creates a snapshot on the source pool every time it is called.
- then it figures out the last snapshot on the destination pool that matches to one on the source pool.
- it sends the snapshot from the source to the destination.
- removes old snapshots on the source - it keeps just n-snapshots.
- removes old snapshots on the destination - time machine fashion : 5min/last day, 1 hour last week, 1 day last 3 months, 1 week thereafter


How to install
--------------

Right now edit the first four variables in the script according to your setup.
Add it to crontab and you are set.


My current setup looks like this:

	$ zfs list
	puddle         181Gi  19.3Gi  175Gi  /Local
	tank           708Gi  911Gi  371Ki  /Volumes/tank
	tank/puddle    167Gi  911Gi  163Gi  /Volumes/tank/puddle

/Local is where my home directory lives. The script is setup as follows:

	my $sourcepool					= 'puddle';
	my $destinationpool				= 'tank/puddle';
	my $snapshotstokeeponsource		= 100;	
	

So puddle is set as source, tank/puddle will receive the snapshots from puddle and 100 snapshots are kept on puddle itself.

If you want to change the times when backups are removed on the destination you can change the following hash:

	my %buckets = 	(	1	*24*3600	=> 			5*60,	# last day every 5 minutes
						7	*24*3600 	=> 			3600,	# last 7 days, every hour
						90	*24*3600	=> 1	*24*3600,	# last 90 days, every day
					);

	my $buckettime = 7*24*3600; # keep weekly backups for beyond the time specified in %buckets.



