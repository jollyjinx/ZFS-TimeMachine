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
#	example usage: perl zfstimemachinebackup.perl  --sourcepool=puddle --destinationpool=tank/puddle
#



use JNX::Configuration;

my %commandlineoption = JNX::Configuration::newFromDefaults( {																	
																	'sourcepool'							=>	['puddle','string'],
																	'snapshotsonsource'						=>	[100,'number'],
																	'destinationpool'						=>	['ocean/puddle','string'],
# not used yet														'destinationhost'						=>	['','string'],
																	'replicate'								=>	[0,'flag'],
																	'createdestinationsnapshotifneeded'		=>	[1,'flag'],
															 }, __PACKAGE__ );



my $sourcepool 								= $commandlineoption{sourcepool};
my $destinationpool							= $commandlineoption{destinationpool};
my $snapshotstokeeponsource					= $commandlineoption{snapshotsonsource};	


######################################
use strict;
use English;
use POSIX qw(strftime);
use Time::Local;
use Digest::MD5 qw(md5_hex);

$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';

sub getsnapshotsforpool;
sub checkforrunningmyself;
sub pidfilename;


####
# create a new snapshot
####
my $snapshotdate	= strftime "%Y-%m-%d-%H%M%S", localtime;

print 'Date for this snapshot: '.$snapshotdate."\n";
`zfs snapshot "$sourcepool\@$snapshotdate"`;


####
# prevent us from running twice
####
checkforrunningmyself($sourcepool.$destinationpool) || die "Already running";


####
# figure out existing snapshots on both pools
####
my @sourcesnapshots 		= getsnapshotsforpool($sourcepool);
my @destinationsnapshots	= getsnapshotsforpool($destinationpool);
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
	my $zfsbugworkaroundintermediatefifo = "/tmp/intermediate.$snapshotdate.".md5_hex($sourcepool.$destinationpool) ;

	`mkfifo "$zfsbugworkaroundintermediatefifo"`;		# workaround is needed as the 2012-01-13 panics the machine if zfs send pipes to zfs receive

	
	if( 0 == ( my $pid = fork() ) )
	{
		my $replicate = $commandlineoption{replicate}?' -R':undef;
		
		if( $lastcommonsnapshot )
		{
			`zfs send -I "$sourcepool\@$lastcommonsnapshot" "$sourcepool\@$snapshotdate" > "$zfsbugworkaroundintermediatefifo" `;
		}
		else
		{
			`zfs send$replicate "$sourcepool\@$snapshotdate" > "$zfsbugworkaroundintermediatefifo" `;
		}
		exit;
	}
	else
	{
		die "Could not fork zfs send" if $pid<0
	}
	`zfs receive -F "$destinationpool" < "$zfsbugworkaroundintermediatefifo"`;
	
	unlink($zfsbugworkaroundintermediatefifo);
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
	
	if( !$lastcommonsnapshot && ( @snapshotstodelete > $snapshotstokeeponsource ) )
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
	if( $snapshotname =~ /^(20\d{2})\-(\d{2})\-(\d{2})\-(\d{2})(\d{2})(\d{2})$/ )
	{
		my($year,$month,$day,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
		my $snapshottime = timelocal($second,$minute,$hour,$day,$month-1,$year);
		
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

sub getsnapshotsforpool($)
{
	my($pool) 		= @_;
	my @snapshots;
	
	open(FILE,'zfs list -t snapshot |') || die "can't read snapshots: $!";
	
	while( $_ = <FILE>)
	{
		if( /^\Q$pool\E@(\S+)\s/ )
		{
			push(@snapshots,$1) if length $1>0;
		}
	}
	close(FILE);
	
	return @snapshots;
}

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


sub pidfilename($)
{
        my ($runcheckname) = @_;

        my $rsynchashname = undef;

        if( length $runcheckname )
        {
                $rsynchashname = md5_hex($runcheckname).'.';
        }

        my $prgname = $PROGRAM_NAME;

        $prgname =~ s/^(.*\/)//;
        $prgname =~ s/\s+//g;
        $prgname .= '.' if length($prgname);

        return '/private/tmp/.'.$prgname.$rsynchashname.'PID';
}

sub checkforrunningmyself($)
{
        my ($runcheckname) = @_;

        my $filename = pidfilename($runcheckname);

        if( open(FILE,$filename) )
        {
                my $otherpid = <FILE>;
                close(FILE);

                if( kill(0,int($otherpid)) )
                {
                        return 0;
                }
        }
        open(FILE,'>'.$filename) || die "Can't open pid file";
        print FILE $$;
        close(FILE);

        return 1;
}
