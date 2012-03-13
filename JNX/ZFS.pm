package JNX::ZFS;

use strict;
use Time::Local;
use Date::Parse;
use POSIX qw(strftime);




$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';

sub onlinepools()
{
	open(FILE,'zpool status|') || die "Can't list pools";
	
	my %pools;

	my($poolname,$status,$lastscan);

	while( $_ = <FILE> )
	{
		$poolname	= $1	if /^\s*pool:\s*(\S+)/i;
		$status		= $1	if /^\s*state:\s*(\S+)/i;
		$lastscan	= $1	if /^\s*scan:\s*(.*)/i;
	
		if( /^\s*errors:/i )
		{
			$pools{$poolname}{status}	= $status ;

											#scan: scrub repaired 0 in 43h24m with 0 errors on Thu Mar  8 09:38:35 2012
			if( $lastscan =~ m/with\s+(\d+)\s+errors\s+on\s+(.*?)$/ )
			{
				$pools{$poolname}{scanerrors}	= $1;
				$pools{$poolname}{lastscan}	= str2time($2);
			}
			$poolname	= undef;
			$status		= undef;
			$lastscan	= undef;
		}
	}
	close(FILE);
	
	return \%pools;
}

sub createsnapshotforpool($)
{
	my($pool)		= @_;
	return createsnapshotforpoolandhost($pool,undef);
}

sub createsnapshotforpoolandhost($$)
{
	my($pool,$host)		= @_;
	
	my $snapshotdate	= strftime "%Y-%m-%d-%H%M%S", localtime;

	my $snapshotname	= $pool.'@'.$snapshotdate;
	`zfs snapshot "$snapshotname"`;
	
	my @snapshots = getsnapshotsforpool($pool,$host);
	
	for my $name (reverse @snapshots)
	{
		return $snapshotname if $name eq $snapshotdate;
	}
	print STDERR "Could not create snapshot:".$snapshotname."\n";
	return undef;
}

sub getsnapshotsforpool($)
{
	my($pool)		= @_;
	return getsnapshotsforpoolandhost($pool,undef);
}

sub getsnapshotsforpoolandhost($$)
{
	my($pool,$host)		= @_;
	my @snapshots;
	
	
	open(FILE,($host?'ssh '.$host.' ':'').'zfs list -t snapshot |') || die "can't read snapshots: $!";
	
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


sub timeofsnapshot($)
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


1;
