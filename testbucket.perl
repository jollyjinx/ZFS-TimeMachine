use strict;
use feature "state";
use POSIX qw(strftime EXIT_FAILURE);
use Data::Dumper;

#my $timebuckets	= jnxparsetimeperbuckethash( '24h=>5min,7d=>1h,90d=>1d,1y=>1w,10y=>1month' );

my $timebuckets	= jnxparsetimeperbuckethash( '10sec=>2sec,20sec=>3sec,1m=>5sec,24h=>5min,7d=>1h,90d=>1d,1y=>1w,10y=>1month' );
	
print Data::Dumper->Dumper($timebuckets)."\n";


my $scriptstarttime		= undef;
my %commandlineoption 	= { 'debug'=>1 };


my $realtime= time();
my @bucketfunctions = ( \&buckettimefortime1a, \&buckettimefortime1b, \&bucketfortimeold );

my %snapshots;

for my $functionnumber (0..$#bucketfunctions)
{
	$snapshots{$functionnumber} = [];
}

my $starttime = 1359763166-(1359763166%3600);
my $starttime = 1259763166-(1259763166%3600);
my $starttime = 1059763166-(1259763166%3600);

for(my $virtualtime=$starttime; $virtualtime < $realtime; $virtualtime += 3600 )
{
	$scriptstarttime = $virtualtime + int(rand(3000));

	
	my $haschangedflag = 0;
	for my $functionnumber (0..$#bucketfunctions)
	{
		my $snapshotarray = $snapshots{$functionnumber};
		
		push(@{$snapshotarray},$virtualtime);
	
		my $newsnapshotarray = removeunneededsnapshots($functionnumber,$snapshotarray);
		
		$haschangedflag +=  abs($#{$snapshotarray}-1 - $#{$newsnapshotarray});
		
	
		
		$snapshots{$functionnumber} = $newsnapshotarray;
	}
	
	if( $haschangedflag >1 )
	{
		printf "Created snapshot : %s %d\t",''.localtime($scriptstarttime),$scriptstarttime;
		for my $functionnumber (0..$#bucketfunctions)
		{
			printf "\t%d:%5s",$functionnumber,$#{$snapshots{$functionnumber}};
		}
		printf "\t%d\n",$haschangedflag;
	}
}




exit;
my %buckethash;

for my $j (0)#(0..10000 )
{
	$scriptstarttime = $realtime - $j;

    for (my $i = 0; $i < 20000000000; $i+=177) 
   # for (my $i = 20000000000; $i >0; $i-=2) 
	{
		my $timetotest	= $scriptstarttime - $i;
		
		#printf "TimetoTest: %s %d ",''.localtime($timetotest),$timetotest;
		
		for my $functionnumber (0..$#bucketfunctions)
		{
			my $function = $bucketfunctions[$functionnumber];
			my $result = &$function($timetotest);
			my %results;
			#printf "\t%d:%d",$functionnumber,$result;
			if( ! defined $buckethash{$functionnumber}{$result} )
			{
				$buckethash{$functionnumber}{$result} = $timetotest;
				$results{$functionnumber}{time}		= $timetotest;
				$results{$functionnumber}{result} 	= $result;
				#printf "%d",$result;
			}
			else
			{
				#printf "\t$buckethash{$functionnumber}{$result}";
			}
			
			if( keys(%results) )
			{
				printf "TimetoTest: %s %d ",''.localtime($timetotest),$timetotest;
				for my $functionnumber (0..$#bucketfunctions)
				{
					printf "\t%20s",$results{$functionnumber}{time}==$timetotest?$results{$functionnumber}{result}:"-";
				}
				print "\n";
			}
		}
#		print "\n";
	}
}

exit;


sub removeunneededsnapshots
{
	my ($functionnumber,$snapshotdates)	= @_;
	
	my %buckethash;
	my $function = $bucketfunctions[$functionnumber];
	
	for my $snapshotdate (@{$snapshotdates})
	{
		my $result = &$function($snapshotdate);
		
		if( !defined $buckethash{$result} )
		{
			$buckethash{$result} = $snapshotdate;
		}
	}
	return [sort(values(%buckethash))];
}





sub buckettimefortime1a
{
	my($timetotest)	= @_;

	state $sortedbucketsvalues   = [ sort{ $a<=>$b }( values %{$timebuckets}) ];
    state $sortedbucketskeys	 = [ sort{ $a<=>$b }( keys %{$timebuckets} )  ];
        
    state $calledonce = 0;
    
    if( !$calledonce)
    {
		$calledonce = 1;
		print "\nsortedbucketsvalues:",join(",",@{$sortedbucketsvalues})."\n";
		print "sortedbucketskeys:",join(",",@{$sortedbucketskeys})."\n";
	}


	my $timedistance    = $scriptstarttime - $timetotest;           #

#	printf "%s scriptstarttime: %s bucketstarttime: %s timedistance %d\n",__PACKAGE__.'['.__LINE__.']:',''.localtime($scriptstarttime),''.localtime($bucketstarttime),''.localtime($timetotest);


	my $buckettime	= (sort( values %{$timebuckets} ))[-1];         # default is to put it in the last bucket and see if there are earlier buckets

	for my $bucketage  (@{$sortedbucketskeys})
	{
		if( $timedistance < $bucketage )
		{
			$buckettime = $$timebuckets{$bucketage};
			last;
		}
	}
#	print "Buckettime: $buckettime\n";
	
    my $buckettimetouse = $scriptstarttime - ($scriptstarttime % $buckettime) + $buckettime; # align 
	
	my $bucket 	= $timetotest - ($timetotest%$buckettime);#int($timedistance/$buckettime)*$buckettime;
	my $bucketb = int($timedistance/$buckettime)*$buckettime;
	
	print __PACKAGE__.'['.__LINE__.']:'."Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n" if $commandlineoption{debug};
	
	return $bucket;
}


sub buckettimefortime1b
{
	my($timetotest)	= @_;

	if( $timetotest > $scriptstarttime )
	{
		print __PACKAGE__.'['.__LINE__.']:'."Time found in snapshot:".localtime($timetotest)." is in the future - exiting\n";
		exit EXIT_FAILURE;
	}

	state $sortedbucketsvalues   = [ sort{ $a<=>$b }( values %{$timebuckets}) ];
    state $sortedbucketskeys	 = [ sort{ $a<=>$b }( keys %{$timebuckets} )  ];
        
	my $timedistance    = $scriptstarttime - $timetotest;
	my $buckettime		= $$sortedbucketsvalues[-1];         # default is to put it in the last bucket and see if there are earlier buckets

	for my $bucketage  (@{$sortedbucketskeys})
	{
		if( $timedistance < $bucketage )
		{
			$buckettime = $$timebuckets{$bucketage};
			last;
		}
	}
    my $buckettimetouse = $scriptstarttime - ($scriptstarttime % $buckettime) + $buckettime; # align 	
	my $bucket 			= $timetotest - ($timetotest%$buckettime);
	
	print __PACKAGE__.'['.__LINE__.']:'."Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n" if $commandlineoption{debug};
	
	return $bucket;
}




sub buckettimefortime2
{
	my($timetotest)	= @_;

	state $sortedbucketsvalues   = [ sort{ $a<=>$b }( values %{$timebuckets}) ];
    state $sortedbucketskeys	 = [ sort{ $a<=>$b }( keys %{$timebuckets} )  ];
        
    state $calledonce = 0;
    
    if( !$calledonce)
    {
		$calledonce = 1;
		print "sortedbucketsvalues:",join(",",@{$sortedbucketsvalues})."\n";
		print "sortedbucketskeys:",join(",",@{$sortedbucketskeys})."\n";
	}


	my $timedistance    = $scriptstarttime - $timetotest;           #

#	printf "%s scriptstarttime: %s bucketstarttime: %s timedistance %d\n",__PACKAGE__.'['.__LINE__.']:',''.localtime($scriptstarttime),''.localtime($bucketstarttime),''.localtime($timetotest);


	my $buckettime	= (sort( values %{$timebuckets} ))[-1];         # default is to put it in the last bucket and see if there are earlier buckets

	for my $bucketage  (@{$sortedbucketskeys})
	{
		if( $timedistance < $bucketage )
		{
			$buckettime = $$timebuckets{$bucketage};
			last;
		}
	}
#	print "Buckettime: $buckettime\n";
	
    my $buckettimetouse = $scriptstarttime - ($scriptstarttime % $buckettime) + $buckettime; # align 
	
	my $bucket = $timetotest - ($timetotest%$buckettime);#int($timedistance/$buckettime)*$buckettime;
#	my $bucketb = int($timedistance/$buckettime)*$buckettime;
	
	print __PACKAGE__.'['.__LINE__.']:'."Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n" if $commandlineoption{debug};
	
	return $bucket;
}



sub bucketfortimeold
{
	my($timetotest)	= @_;

	my $timedistance    = $scriptstarttime - $timetotest;
   
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
	print __PACKAGE__.'['.__LINE__.']:'."Timedistance: $timedistance , $timetotest, ".localtime($timetotest)." buckettime:$buckettime bucket:$bucket\n" if $commandlineoption{debug};
	
	return $bucket;
}


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
	print STDERR __PACKAGE__.'['.__LINE__.']:'."Created buckethash:".Data::Dumper->Dumper(\%timehash) if $commandlineoption{debug};

	return \%timehash;
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
