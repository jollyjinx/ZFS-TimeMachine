package JNX::ZFS;
use strict;
use Time::Local qw(timelocal);
use Date::Parse qw(str2time);
use POSIX qw(strftime);



use JNX::Configuration;

my %commandlineoption = JNX::Configuration::newFromDefaults( {																	
																	'verbose'								=>	[0,'flag'],
																	'debug'									=>	[0,'flag'],
															 }, __PACKAGE__ );


$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';



=head1 ZFS::pools

return hash of %{poolname}{scanerrors => \d ,lastscrub => time, status => string }
=cut


sub pools
{
	my %pools;
	my($poolname,$status,$lastscrub);

	foreach (JNX::System::executecommand( @_, command=>'zpool status'))
	{
		$poolname	= $1	if /^\s*pool:\s*(\S+)/i;
		$status		= $1	if /^\s*state:\s*(\S+)/i;
		$lastscrub	= $1	if /^\s*scan:\s*(.*)/i;
	
		if( /^\s*errors:/i )
		{
			$pools{$poolname}{status}	= $status ;

											#scan: scrub repaired 0 in 43h24m with 0 errors on Thu Mar  8 09:38:35 2012
			if( $lastscrub =~ m/with\s+(\d+)\s+errors\s+on\s+(.*?)$/ )
			{
				$pools{$poolname}{scanerrors}	= $1;
				$pools{$poolname}{lastscrub}	= str2time($2);
			}
			elsif( $lastscrub =~ m/scrub\s+canceled\s+on\s+(.*?)$/ )
			{
				$pools{$poolname}{lastscrub}	= str2time($1);
			}
			elsif( $lastscrub =~ m/^scrub in progress/i )
			{
				$pools{$poolname}{lastscrub}	= time();
			}
			$poolname	= undef;
			$status		= undef;
			$lastscrub	= undef;
		}
	}
	return \%pools;
}



=head1 ZFS::createsnapshot

Creates a snapshot with the current date on the given host and dataset
	
Arguments:	{dataset,recursive}

Arguments are also given to System::executecommand()

Returns: undef or snapshotname in 'YYYY-mm-dd-HHMMSS' format
=cut


sub createsnapshot
{
	my %arguments = @_;

	return undef if !length( $arguments{dataset} );

	my $snapshotdate	= strftime "%Y-%m-%d-%H%M%S", localtime;
	my $snapshotname	= $arguments{dataset}.'@'.$snapshotdate;

	return undef if !defined(JNX::System::executecommand( %arguments, command => 'zfs snapshot '.($arguments{recursive}?'-r ':'').'"'.$arguments{dataset}.'@'.$snapshotdate.'"'));

	print STDERR "Created Snapshot: $snapshotname\n" if $commandlineoption{verbose};

	my @snapshots = getsnapshotsfordataset( %arguments );
	
	for my $name (reverse @snapshots)
	{
		print STDERR "Testing Snapshot: $name\n" if $commandlineoption{verbose};
		return $snapshotname if $name eq $snapshotdate;
	}
	print STDERR 'Could not create snapshot:'.$snapshotname."\n";
	return undef;
}


=head1 ZFS::getsnapshotsfordataset

Gets a list of snaphots for the host and datset

Arguments:	{dataset}

Arguments are also given to System::executecommand()

Returns: a list of snapshots for the given dataset
=cut
my %snapshotcache;
my %datasetcache;


sub getsnapshotsfordataset
{
	my %arguments = @_;

	return undef if !length( $arguments{dataset} );
	$arguments{host} = 'localhost' if !length( $arguments{host} );


	if( time()-$snapshotcache{$arguments{host}}{lasttime}{$arguments{dataset}} > 500 )
	{
		delete $snapshotcache{$arguments{host}};
		$snapshotcache{$arguments{host}}{lasttime}{$arguments{dataset}}=time();

		for (JNX::System::executecommand( %arguments, command => 'zfs list -H -t snapshot -o name -s name -d 1 -r "'.$arguments{dataset}.'"'))
		{
			if( /^([A-Za-z0-9\_\-\s\/\.]+)\@(\S+)\s/ )
			{
				print STDERR "Got Snapshot: $arguments{host}: $1\@$2 \n";
				push(@{$snapshotcache{$arguments{host}}{datasets}{$1}},$2) if length $2>0;
			}
			else
			{
			#	print STDERR "Did not match: $_\n";
			}
		}
	}
	else
	{
		print STDERR "Serving from cache\n";
	}
	my $snapshotsref = $snapshotcache{$arguments{host}}{datasets}{$arguments{dataset}};

	return $snapshotsref?@{$snapshotsref}:();
}





=head1 ZFS::getsubdatasets

Returns a list of datasets that are equal and below a given one

Arguments:	{dataset}

Arguments are also given to System::executecommand()
=cut


sub getsubdatasets
{
	my %arguments = @_;

	return undef if !length( $arguments{dataset} );
	$arguments{host} = 'localhost' if !length( $arguments{host} );

	if( time()-$datasetcache{$arguments{host}}{cachetime} > 500 )
	{
		$datasetcache{$arguments{host}}{cachetime}=time();

		my @datasets;
	
		for (JNX::System::executecommand( %arguments, command => 'zfs list -H -r -o name') )
		{
			chomp;
			if( /^([A-Za-z0-9\_\-\s\/\.]+)$/ )
			{
				push(@datasets,$1);
			}
			else
			{
				print STDERR "Did not match: $_\n";
			}
		}
		
		$datasetcache{$arguments{host}}{datasets}=\@datasets;
	}
	return grep(/^\Q$arguments{dataset}\E/, @{$datasetcache{$arguments{host}}{datasets}});
}





sub timeofsnapshot
{
	my ($snapshotname) = @_;
	
	if( $snapshotname =~ /(?:^|@)(2\d{3})\-(\d{2})\-(\d{2})\-(\d{2})(\d{2})(\d{2})$/ )
	{
		my($year,$month,$day,$hour,$minute,$second) = ($1,$2,$3,$4,$5,$6);
		my $snapshottime = timelocal($second,$minute,$hour,$day,$month-1,$year);
		
		return $snapshottime;
	}
	return 0;
}


=head1 ZFS::destroysnapshots

Destroys a snapshots or list of snapshots ( dataset@snapshotname )

Arguments:	{ snapshot }

Arguments are also given to System::executecommand()
=cut

sub destroysnapshots
{
	my %arguments = @_;

	return undef if !$arguments{dataset};
	return undef if !$arguments{snapshots};

	$arguments{host} = 'localhost' if !length( $arguments{host} );
	delete $snapshotcache{$arguments{host}};

	my @snapshotstodelete;

	if( ref($arguments{snapshots}) eq "ARRAY" )
	{
		@snapshotstodelete = @{$arguments{snapshots}};
	}
	else
	{
		@snapshotstodelete = ($arguments{snapshots});
	}
	


	foreach my $snapshot (@snapshotstodelete)
	{
		JNX::System::executecommand( %arguments, command => 'zfs destroy "'.$arguments{dataset}.'@'.$snapshot.'"', debug=>$commandlineoption{debug} );
	}
}


1;
