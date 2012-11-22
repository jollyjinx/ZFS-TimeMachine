#!/usr/bin/perl
#
# purpose:	simple script to automatically scub zpools when needed
#
#	example usage: perl autoscrub.perl  --scrubinterval=7
#
#	this will start a scrub on all pools if the last scrub was 7 days or longer ago
#



use JNX::Configuration;

my %commandlineoption = JNX::Configuration::newFromDefaults( {																	
																	'pools'							=>	['allavailablepools','string'],
																	'scrubinterval'				=>	[7,'number'],
															 }, __PACKAGE__ );

use strict;

use JNX::ZFS;
use JNX::System;

my %pools	= %{ JNX::ZFS::pools() };
my @scrubpools;

if( $commandlineoption{pools} eq 'allavailablepools' )
{
	@scrubpools = (keys %pools);
}
else
{
	@scrubpools = split( /[,\s]/,$commandlineoption{pools} );
}



for my $pool (@scrubpools )
{
	if( defined $pools{$pool} )
	{
		if( $pools{$pool}{lastscrub} < ( time() - (86400*$commandlineoption{scrubinterval})) ) 
		{
			system('zpool scrub '.$pool) && die "could not start scrub: $!";
			print "$pool: starting scrub \n";
		}
		else
		{
			print "$pool: no scrub needed\n";
		}
	}
}


