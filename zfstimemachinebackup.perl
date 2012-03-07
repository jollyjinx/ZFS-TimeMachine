#!/usr/bin/perl
# author: 	patrick stein aka jolly
# date:	  	2012-01-25
# purpose:	simple zfs backup from one pool to another via sending snapshots, deleting old ones in time machine style.
#
#	the script creates a snapshot on the source pool every time it is called
# 	then it figures out the last snapshot on the destination pool that matches to one on the source pool
#	it sends the snapshot from the source to the destination
#	removes old snapshots on the source - it keeps just n-snapshots
#	removes old snapshots on the destination - time machine fashion ( 5min/last day, 1 hour last week, 1 day last 3 months, 1 week thereafter )
#
#
#
#	example usage: perl zfstimemachinebackup.perl  --sourcepool=puddle --destinationpool=tank/puddle --snapshotstokeeponsource=100 --createsnapshotonsource
#



use JNX::Configuration;

my %commandlineoption = JNX::Configuration::newFromDefaults( {																	
																	'sourcepool'							=>	['puddle','string'],
																	'createsnapshotonsource'				=>	[0,'flag'],
																	'snapshotstokeeponsource'				=>	[0,'number'],
																	'destinationpool'						=>	['ocean/puddle','string'],
																	'destinationhost'						=>	['','string'],
																	'replicate'								=>	[0,'flag'],
																	'createdestinationsnapshotifneeded'		=>	[1,'flag'],
															 }, __PACKAGE__ );



my $sourcepool 								= $commandlineoption{sourcepool};
my $destinationhost							= $commandlineoption{destinationhost};
my $destinationpool							= $commandlineoption{destinationpool};
my $snapshotstokeeponsource					= $commandlineoption{snapshotstokeeponsource};	


######################################
use strict;
use POSIX qw(strftime);

use JNX::ZFS;
use JNX::System;

$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';

####
# create a new snapshot
####

if( $commandlineoption{createsnapshotonsource} )
{
	my $newsnapshotname	= JNX::ZFS::createsnapshotforpool($sourcepool) || die "Could not create snapshot on $sourcepool";
}

####
# prevent us from running twice
####
JNX::System::checkforrunningmyself($sourcepool.$destinationpool) || die "Already running";


####
# figure out existing snapshots on both pools
####
my @sourcesnapshots 		= JNX::ZFS::getsnapshotsforpool($sourcepool);
my @destinationsnapshots	= JNX::ZFS::getsnapshotsforpoolandhost($destinationpool,$destinationhost);

if( ! @sourcesnapshots )
{
	die "Did not find snapshot on source pool";
}

my $lastsourcesnapshot	= @sourcesnapshots[$#sourcesnapshots];
my $snapshotdate		= strftime "%Y-%m-%d-%H%M%S", localtime(JNX::ZFS::timeofsnapshot($lastsourcesnapshot));


my $lastcommonsnapshot 		= undef;

{
	my %knownindestination;
	@knownindestination{@destinationsnapshots} = @destinationsnapshots;
	
	
	for my $snapshotname (@sourcesnapshots)
	{
		$lastcommonsnapshot = $snapshotname if $knownindestination{$snapshotname};
	}
	
	if( !$lastcommonsnapshot )
	{
		print "Could not find common snapshot\n";
	
		if( ! $commandlineoption{createdestinationsnapshotifneeded} )
		{
			die;
		}
	}
	else
	{
		print 'Last common snapshot:   '.$lastcommonsnapshot."\n";
	}
}

####
# send new snapshot diff to destination
####
{
	my $zfssendcommand		= undef;
	my $zfsreceivecommand	= 'zfs receive -F "'.$destinationpool.'"';
	
	if( $lastcommonsnapshot )
	{
		$zfssendcommand	= 'zfs send -I "'.$sourcepool.'@'.$lastcommonsnapshot.'" "'.$sourcepool.'@'.$snapshotdate.'"';
	}
	else
	{
		$zfssendcommand	= 'zfs send '.($commandlineoption{replicate}?'-R ':undef).'"'.$sourcepool.'@'.$snapshotdate.'"';
	}
	
	if($destinationhost)
	{
		`$zfssendcommand | (ssh $destinationhost $zfsreceivecommand)`;
	}
	else
	{
		
		my $zfsbugworkaroundintermediatefifo = JNX::System::temporaryfilename($snapshotdate,$sourcepool.$destinationpool);

		`mkfifo "$zfsbugworkaroundintermediatefifo"`;		# workaround is needed as the 2012-01-13 panics the machine if zfs send pipes to zfs receive

		
		if( 0 == ( my $pid = fork() ) )
		{
			`$zfssendcommand > "$zfsbugworkaroundintermediatefifo"`;
			exit;
		}
		else
		{
			die "Could not fork zfs send" if $pid<0
		}
		`$zfsreceivecommand < "$zfsbugworkaroundintermediatefifo"`;
	
		unlink($zfsbugworkaroundintermediatefifo);
	}
}

####
# delete unneeded snapshots in source
####
{
	my @snapshotstodelete = undef;

	for my $snapshotname (@sourcesnapshots)
	{
		if( $lastcommonsnapshot eq $snapshotname )
		{
			$lastcommonsnapshot = undef;
			last;
		}
		push(@snapshotstodelete,$snapshotname);
	}
	
	if( $snapshotstokeeponsource>1 && !$lastcommonsnapshot && ( @snapshotstodelete > $snapshotstokeeponsource ) )
	{
		splice(@snapshotstodelete,-1* $snapshotstokeeponsource);
		
		print 'Snapshots to delete on source: '.join(',',@snapshotstodelete)."\n";
		
		sleep 1;
		for my $snapshotname (@snapshotstodelete)
		{
			`zfs destroy "$sourcepool\@$snapshotname"` if length($snapshotname);
		}
	}
}


####
# remove old snapshots in time machine fashion from destination
####

my %backupbuckets;

for my $snapshotname (reverse @destinationsnapshots )
{
	if( my $snapshottime = JNX::ZFS::timeofsnapshot($snapshotname) )
	{		
		my $bucket = bucketfortime($snapshottime);
		
		if( ! $backupbuckets{$bucket} )
		{
			$backupbuckets{$bucket}=$snapshotname;
			print 'Will keep snapshot:  '.$snapshotname.'='.$snapshottime.' Backup in bucket: $backupbucket{'.$bucket.'}='.$backupbuckets{$bucket}."\n";
		}
		else
		{
			print 'Will remove snapshot:'.$snapshotname.'='.$snapshottime.' Backup in bucket: $backupbucket{'.$bucket.'}='.$backupbuckets{$bucket}."\n";
			`zfs destroy "$destinationpool\@$snapshotname"`;
		}
	}
	else
	{
		print "snapshot not in YYYY-MM-DD-HHMMSS format: $snapshotname - ignoring\n";
	}
}


exit;


sub bucketfortime($)
{
	my($timetotest)	= @_;
	
	my $timedistance = time() - $timetotest;
	
	
	my %buckets = 	(	1	*24*3600	=> 			5*60,	# last day every 5 minutes
						7	*24*3600 	=> 			3600,	# last 7 days, every hour
						90	*24*3600	=> 1	*24*3600,	# last 90 days, every day
					);

	my $buckettime = 7*24*3600; # keep weekly backups for beyond the time specified in %buckets.


	for my $bucketage  (sort{ $a<=>$b }( keys %buckets ))
	{
		if( $timedistance < $bucketage )
		{
			$buckettime = $buckets{$bucketage};
			last;
		}
	}
	
	my $bucket = int($timedistance/$buckettime)*$buckettime;
#	print "Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n";
	
	return $bucket;
}

