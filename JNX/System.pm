
package JNX::System;

use strict;
use English;
#use Date::Parse;
use Digest::MD5 qw(md5_hex);


sub boottime
{
	open(FILE,"sysctl kern.boottime|")	|| return 0;
	
	my $lastboottime	= 0;
	
	while( my $line = <FILE> )
	{
		$lastboottime = $1 if $line =~ /^kern.boottime:\s*\{\ssec\s*=\s(\d+),/;
	}
	close(FILE);
	
	return $lastboottime;

}

sub lastwaketime
{
	open(FILE,"pmset -g log|")	|| return 0;
	
	my $lastwaketime	= 0;
	my $message			= undef;
	
	my $line;
	do
	{
		$line = <FILE>;
		$message .= $line;
		
		if( $line =~ /^\s*$/ || !$line )
		{
			
			if( 	(		$message =~ m/^\s+\-\s+Message:\s+Wake:/m 
						&&	$message =~ m/^\s+\-\s+Time:\s+(\S.+)$/m 
					)
				||	( $message =~ m/^20(\d\d\-\d\d\-\d\d.+?)\s+wake\s+\t/m )
				)
			{
				my $waketime = str2time('20'.$1);
				$lastwaketime = $waketime if $waketime > $lastwaketime;
			}
		
			$message = undef;
		}
	}
	while( $line );
	close(FILE);
	
	my $lastboottime = boottime();
	
	return $lastwaketime>$lastboottime?$lastwaketime:$lastboottime;
}

sub temporaryfilename
{
	my($prefix,$tohash) = @_;
	
	my $hashname = undef;
	
	if( length $tohash )
	{
			$hashname = md5_hex($tohash);
	}
	
	my $prgname = $PROGRAM_NAME;
	
	$prgname =~ s/^(.*\/)//;
	$prgname =~ s/\s+//g;
	$prgname .= '.' if length($prgname);
	
	$prefix	.= '.' if length $prefix;
	
	return '/private/tmp/.'.$prgname.$prefix.$hashname;
}

sub pidfilename
{
        my ($runcheckname) = @_;
		
		return	temporaryfilename(undef,$runcheckname).'.PID';
}

	
sub checkforrunningmyself
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


1;