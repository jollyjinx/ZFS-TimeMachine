package JNX::ZFS;

use strict;
use Time::Local;
use POSIX qw(strftime);




$ENV{PATH}=$ENV{PATH}.':/usr/sbin/';

sub createsnapshotforpool($)
{
	my($pool) 			= @_;
	my $snapshotdate	= strftime "%Y-%m-%d-%H%M%S", localtime;

	my $snapshotname	= $pool.'@'.$snapshotdate;
	`zfs snapshot "$snapshotname"`;
	
	my @snapshots = getsnapshotsforpool($pool);
	
	for my $name (reverse @snapshots)
	{
		return $snapshotname if $name eq $snapshotdate;
	}
	print STDERR "Could not create snapshot:".$snapshotname."\n";
	return undef;
}


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