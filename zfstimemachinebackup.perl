#!/usr/bin/perl
# author: 	patrick stein aka jolly
# purpose:	simple zfs backup from one dataset to another via sending snapshots, deleting old ones in time machine style.
#
#	the script creates a snapshot on the source dataset every time it is called
# 	then it figures out the last snapshot on the destination dataset that matches to one on the source dataset
#	it sends the snapshot from the source to the destination
#	removes old snapshots on the source - it keeps just n-snapshots
#	removes old snapshots on the destination - time machine fashion ( 5min/last day, 1 hour last week, 1 day last 3 months, 1 week thereafter )
#
#
#
#	example usage: perl zfstimemachinebackup.perl  --sourcedataset=puddle --destinationdataset=tank/puddle --snapshotstokeeponsource=100 --createsnapshotonsource
#



use JNX::Configuration;

my %commandlineoption = JNX::Configuration::newFromDefaults( {																	
																	'sourcedataset'							=>	['puddle','string'],
																	'createsnapshotonsource'				=>	[0,'flag'],
																	'snapshotstokeeponsource'				=>	[0,'number'],
																	'minimumtimetokeepsnapshotsonsource'	=>	['','string'],
																	'destinationdataset'					=>	['ocean/puddle','string'],
																	'destinationhost'						=>	['','string'],
																	'replicate'								=>	[0,'flag'],
																	'deduplicate'							=>	[0,'flag'],
																	'createdestinationsnapshotifneeded'		=>	[1,'flag'],
																	'deletesnapshotsondestination'			=>	[1,'flag'],
				
																	'recursive'								=>	[0,'flag'],
																	'keepbackupshash'						=>	['24h=>5min,7d=>1h,90d=>1d,1y=>1w,10y=>1month','string'],
																	'maximumtimeperfilesystemhash'			=>	['.*=>10yrs,.+/(Dropbox|Downloads|Caches|Mail Downloads|Saved Application State|Logs)$=>1month','string'],

																	'verbose'								=>	[0,'flag'],
																	'debug'									=>	[0,'flag'],
															 }, __PACKAGE__ );



my $timebuckets								= jnxparsetimeperbuckethash( $commandlineoption{keepbackupshash}	);
my @maximumtimebuckets						= jnxparsetimeperfilesystemhash( $commandlineoption{maximumtimeperfilesystemhash}	);
my $destinationhost							= $commandlineoption{destinationhost};
my $snapshotstokeeponsource					= $commandlineoption{snapshotstokeeponsource};	
my $minimumtimetokeepsnapshotsonsource		= jnxparsesimpletime( $commandlineoption{minimumtimetokeepsnapshotsonsource} );


if( $commandlineoption{debug} )
{
	$commandlineoption{verbose}=1;
	
	use Data::Dumper;

	print STDERR Data::Dumper->Dumper($timebuckets)."\n";
	print STDERR Data::Dumper->Dumper($maximumtimebuckets)."\n";
}

######################################
use strict;
use POSIX qw(strftime);

use JNX::ZFS;
use JNX::System;

$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';

####
# create a new snapshot
####

my $newsnapshotname = undef;

if( $commandlineoption{createsnapshotonsource} )
{
	$newsnapshotname	= JNX::ZFS::createsnapshotfordataset($commandlineoption{sourcedataset},$commandlineoption{recursive}) || die "Could not create snapshot on $commandlineoption{sourcedataset}";

	print 'Created '.($commandlineoption{recursive}?'recursive ':undef).'snapshot '.$newsnapshotname."\n";
}

####
# prevent us from running twice
####
JNX::System::checkforrunningmyself($commandlineoption{sourcedataset}.$commandlineoption{destinationdataset}) || die "Already running";

if( my $childpid = fork() )
{
	print "Waiting for working child to exit\n" if $commandlineoption{debug};
	wait;
	
	print "Child work done, deleting pid file\n" if $commandlineoption{debug};
	my $pidfile = JNX::System::pidfilename($commandlineoption{sourcedataset}.$commandlineoption{destinationdataset});
	unlink($pidfile);
	exit;
}


{
	my @sourcefilesystems		= ( $commandlineoption{sourcedataset} );

	if( $commandlineoption{recursive} )
	{
		@sourcefilesystems		= JNX::ZFS::getsubfilesystemsondataset($commandlineoption{sourcedataset});
	}


	for my $sourcedataset (@sourcefilesystems)
	{
		my $destinationdataset	= $sourcedataset;

		$destinationdataset		=~ s/^\Q$commandlineoption{sourcedataset}\E/$commandlineoption{destinationdataset}/;

		my $maximumtimeforfilesystem = 0;

		REGEXTEST: for my $regexandvaluearray (reverse @maximumtimebuckets)
		{
			my($regex,$value) = (@{$regexandvaluearray});

			if( $sourcedataset =~ m/$regex/ )
			{
				$maximumtimeforfilesystem = $value;
				print "Matched source: $regex $sourcedataset\n" if $commandlineoption{debug};
				last REGEXTEST;
			}
		}

		print STDERR "Working on sourcedataset: $sourcedataset destinationdataset:$destinationdataset  Maximumtime:$maximumtimeforfilesystem\n";

		####
		# figure out existing snapshots on both datasets
		####
		my @sourcesnapshots 		= JNX::ZFS::getsnapshotsfordatasetandhost($sourcedataset,undef);
		my @destinationsnapshots	= JNX::ZFS::getsnapshotsfordatasetandhost($destinationdataset,$destinationhost);

		if( ! @sourcesnapshots )
		{
			die "Did not find snapshot on source dataset";
		}

		my $lastsourcesnapshot	= @sourcesnapshots[$#sourcesnapshots];
		my $snapshotdate		= strftime "%Y-%m-%d-%H%M%S", localtime(JNX::ZFS::timeofsnapshot($lastsourcesnapshot));


		my $lastcommonsnapshot 			= undef;

		{
			my %knownindestination;
			@knownindestination{@destinationsnapshots} = @destinationsnapshots;
			
			
			for my $snapshotname (@sourcesnapshots)
			{
				if( $knownindestination{$snapshotname} )
				{
					$lastcommonsnapshot 			= $snapshotname;
				}
			}
			
			if( !$lastcommonsnapshot )
			{
				print "Could not find common snapshot between source ($sourcedataset) and destination ($destinationdataset)\n";
				print "Destination snapshots:\n\t".join("\n\t",@destinationsnapshots)."\n";
				print "Source snapshots:\n\t".join("\n\t",@sourcesnapshots)."\n";
			
				if( ! $commandlineoption{createdestinationsnapshotifneeded} )
				{	
					die;
				}
			}
			else
			{
				print 'Last common snapshot: '.$lastcommonsnapshot."\n";
				
				if( $commandlineoption{deletesnapshotsondestination} )
				{	
					my @snapshotsnewerondestination = ();
					my $foundlastcommon 			= 0;
					
					for my $snapshotname (@destinationsnapshots)
					{
						if( $snapshotname eq $lastcommonsnapshot )
						{
							$foundlastcommon = 1;
						}
						elsif( $foundlastcommon )
						{
							push( @snapshotsnewerondestination, $snapshotname );
						}
					}
					
					if( @snapshotsnewerondestination )
					{
						print 'Snapshots newer on destination dataset('.$destinationdataset.'):'.$snapshotsnewerondestination[0].(@snapshotsnewerondestination>1?' - '.$snapshotsnewerondestination[-1]:undef)."\n";
						
						for my $snapshotname (@snapshotsnewerondestination)
						{
							JNX::ZFS::destroysnapshotondatasetandhost($snapshotname,$destinationdataset,$destinationhost);
							
							@destinationsnapshots = grep(!/^\Q$snapshotname\E$/,@destinationsnapshots); # grep as delete @destinationsnapshots[$snapshotname] works only on hashes.
						}
					}
				}
			}
		}


		####
		# send new snapshot diff to destination
		####
		if( $lastcommonsnapshot eq $snapshotdate )
		{
			print "Did not find newer snapshot on source $sourcedataset\n" if $commandlineoption{verbose};
		}
		else
		{
			my $zfssendcommand		= undef;
			my $zfsreceivecommand	= 'zfs receive '.($commandlineoption{verbose}?'-v ':undef).'-F "'.$destinationdataset.'"';
			
			if( $lastcommonsnapshot )
			{
				$zfssendcommand	= 'zfs send '.($commandlineoption{verbose}?'-v ':undef).($commandlineoption{deduplicate}?'-D ':undef).'-I "'.$sourcedataset.'@'.$lastcommonsnapshot.'" "'.$sourcedataset.'@'.$snapshotdate.'"';
			}
			else
			{
				$zfssendcommand	= 'zfs send '.($commandlineoption{verbose}?'-v ':undef).($commandlineoption{replicate}?'-R ':undef).($commandlineoption{deduplicate}?'-D ':undef).'"'.$sourcedataset.'@'.$snapshotdate.'"';
			}
			
			if( $destinationhost )
			{
				system($zfssendcommand.' | (ssh -C '.$destinationhost." '".$zfsreceivecommand."')") && die "Can't remote command did fail: $zfssendcommand -> $zfsreceivecommand\n"
			}
			else
			{
				# workaround is needed as the 2012-01-13 panics the machine if zfs send pipes to zfs receive

				my $zfsbugworkaroundintermediatefifo = JNX::System::temporaryfilename($snapshotdate,$sourcedataset.$destinationdataset);
				
				unlink($zfsbugworkaroundintermediatefifo);
				system('mkfifo '."$zfsbugworkaroundintermediatefifo")	&& die "Could not create fifo: $zfsbugworkaroundintermediatefifo";	
				
				if( 0 == ( my $pid = fork() ) )
				{
					system($zfssendcommand.'> "'.$zfsbugworkaroundintermediatefifo.'"') && die "Can't execute $zfssendcommand";
					exit;
				}
				else
				{
					die "Could not fork zfs send" if $pid<0
				}
				
				system($zfsreceivecommand.'< "'.$zfsbugworkaroundintermediatefifo.'"')	&& die "Can't execute $zfsreceivecommand";
			
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
				
				print 'Snapshots to delete on source ('.$sourcedataset.'): '.$snapshotstodelete[0].(@snapshotstodelete>1?' - '.$snapshotstodelete[-1]:undef)."\n";
				
				for my $snapshotname (@snapshotstodelete)
				{
					if( length($snapshotname) )
					{
						if( $minimumtimetokeepsnapshotsonsource > 0 )
						{
							my $snapshottime = JNX::ZFS::timeofsnapshot($snapshotname);
							if( $snapshottime < time()-$minimumtimetokeepsnapshotsonsource )
							{
								JNX::ZFS::destroysnapshotondatasetandhost($snapshotname,$sourcedataset);
							}
						}
						else
						{
							JNX::ZFS::destroysnapshotondatasetandhost($snapshotname,$sourcedataset);
						}
					}
				}
			}
		}


		####
		# remove old snapshots in time machine fashion from destination
		####
		if( $commandlineoption{deletesnapshotsondestination} )
		{
			my %backupbuckets;
			
			for my $snapshotname (reverse @destinationsnapshots )
			{
				if( my $snapshottime = JNX::ZFS::timeofsnapshot($snapshotname) )
				{
					my $bucket 			= bucketfortime($snapshottime);
					my $keepsnapshot	= 1;


					if( $backupbuckets{$bucket} )
					{
						$keepsnapshot = 0;
					}
					elsif( ($maximumtimeforfilesystem > 0) && ((time()-$snapshottime) > $maximumtimeforfilesystem) )
					{
						$keepsnapshot = 0;
					}


					if( $keepsnapshot )
					{
						$backupbuckets{$bucket}=$snapshotname;
						print 'Will keep snapshot:  '.$snapshotname.'='.$snapshottime.' Backup in bucket: $backupbucket{'.$bucket.'}='.$backupbuckets{$bucket}."\n"  if $commandlineoption{verbose};
					}
					else
					{
						print 'Will remove snapshot:'.$snapshotname.'='.$snapshottime.' Backup in bucket: $backupbucket{'.$bucket.'}='.$backupbuckets{$bucket}."\n";
						
						JNX::ZFS::destroysnapshotondatasetandhost($snapshotname,$destinationdataset,$destinationhost)  if !$commandlineoption{debug}
					}
				}
				else
				{
					print STDERR "snapshot not in YYYY-MM-DD-HHMMSS format: $snapshotname - ignoring\n";
				}
			}
		}
	}
}


exit;


sub jnxparsetimeperbuckethash
{
	my($timestring)	= @_;
	my %timehash;

	my @keysandvalues = split(/,/,$timestring);

	foreach my $keyandvalue (@keysandvalues)
	{
		my($key,$value) = split(/=>/,$keyandvalue);

		#print STDERR "Key: $key Value: $value \n";
		if( $key && $value )
		{
			my $keytime		= jnxparsesimpletime($key);
			my $valuetime	= jnxparsesimpletime($value);

		 	print "Found Keytime: $keytime Valuetime: $valuetime \n" if $commandlineoption{verbose};

			if( ($keytime>=0) && ($valuetime>=0) )
			{
				$timehash{$keytime}=$valuetime;
			}
		}
	}
	return \%timehash;
}


sub jnxparsetimeperfilesystemhash
{
	my($timestring)	= @_;
	my @filesystemarray;

	my @keysandvalues = split(/[^\\],/,$timestring);		#	escaping , inside a reges works

	foreach my $keyandvalue (@keysandvalues)
	{
		if( $keyandvalue =~ m/^(.+)=>(.+?)$/ )				#	the right side can't contain a => as it's only a time
		{
			my($key,$value) = ($1,$2);

			$key =~ s/\\,/,/g;								#	replace \, in case someone has a escaped , inside a left regex

			if( $key && $value )
			{
				my $valuetime	= jnxparsesimpletime($value);


				if( length($key)  && ($valuetime>=0) )
				{
					printf "Will use Maximumtime: %8d for filesystem matching:%s\n",$valuetime,$key if $commandlineoption{debug};
					push(@filesystemarray, [$key,$valuetime] );
				}
			}
		}
	}
	return @filesystemarray;
}


sub jnxparsesimpletime
{
	my($timestring)	= @_;

	$timestring	= lc $timestring;

	if( $timestring =~ m/(\d+)\s*(s(?:ec|econds?)?|h(?:ours?)?|d(?:ays?)?|w(:?eeks?)?|m(?:on|onths?)|m(?:ins?|inutes?)?|y(?:rs?|ears?)?)/ )
	{
		my($count,$time) = ($1,$2);

		return	$count*3600*24*364.25	if $time =~ /^y/;
		return	$count*3600*24*30.5		if $time =~ /^mon/;
		return	$count*3600*24*7		if $time =~ /^w/;
		return	$count*3600*24			if $time =~ /^d/;
		return	$count*3600				if $time =~ /^h/;
		return	$count*60				if $time =~ /^m/;
		return	$count;												#defaults to seconds
	}
	return -1;
}

sub bucketfortime
{
	my($timetotest)	= @_;
	
	my $timedistance = time() - $timetotest;
	
	my $buckettime	= (sort( values %{$timebuckets} ))[-1];

	for my $bucketage  (sort{ $a<=>$b }( keys %{$timebuckets} ))
	{
		if( $timedistance < $bucketage )
		{
			$buckettime = $$timebuckets{$bucketage};
			last;
		}
	}
	
	my $bucket = int($timedistance/$buckettime)*$buckettime;
	print "Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n" if $commandlineoption{debug};
	
	return $bucket;
}



