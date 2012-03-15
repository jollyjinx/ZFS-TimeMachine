#
#	name:		Configuration.pm
#	purpose:	one modul for all config tasks
#
#	+ newFromDefaults(hashreference,__PACKAGE__)
#
#

# uses Config ini files if available

package JNX::Configuration;

use Getopt::Long;
use strict;

sub newFromDefaults(%,$)
{
	my($default,$currentpackagename)=@_;
	
	my %default = %{$default} ;
	my %commandlineoption;
	my %returningoptions;
	
	
	if( ! defined($default{'configurationfilename'}) )
	{
		$default{'configurationfilename'}			=	['config.ini','string'];
	}
	if( defined($default{'debug'}) )
	{
		$default{'debug'}	= [int($default{'debug'}[0]),'number'];
	}
	else
	{
		$default{'debug'}	=[0,'number'];
	}
	$default{'help'}	=['','option'];
	
	my %optionconverter = ('string' => '=s', 'number' =>,'=i', 'flag'=>'!','option'=>'', );
	my @ARGVCOPY = @ARGV;
	GetOptions(	\%commandlineoption, map($_.$optionconverter{${$default{$_}}[-1]},keys %default)  );
	@ARGV = @ARGVCOPY;
	my $configfilename = (defined($commandlineoption{'configurationfilename'})?$commandlineoption{'configurationfilename'}:${$default{'configurationfilename'}}[0]);


	my $configurationObject = undef;

	if( eval "require Config::IniFiles" )
	{
		$configurationObject = new Config::IniFiles( -file => $configfilename ) if -e $configfilename;
	}
	else
	{
		$commandlineoption{'configurationfilename'} = 'not used as Config:IniFiles module not present';
	}
	
	
	my $programname	= $0;
	$programname	=~ s/^.*\///;
	my $packagename	= ($currentpackagename eq 'main'?$programname:$currentpackagename);


FILLUPHASH: while( my($key,$value) = each %default )
	{
		if( defined($commandlineoption{$key}) )
		{
			$returningoptions{$key}	= $commandlineoption{$key};
			next FILLUPHASH;
		}
		if( $configurationObject )
		{
			if( defined($configurationObject->val($programname,$key)) )
			{
				$returningoptions{$key} = $configurationObject->val($programname,$key);
				next FILLUPHASH;
			}
			if( defined($configurationObject->val($packagename,$key)) )
			{
				$returningoptions{$key} = $configurationObject->val($packagename,$key);
				next FILLUPHASH;
			}
			if( defined($configurationObject->val('GLOBAL',$key)) )
			{
				$returningoptions{$key} = $configurationObject->val('GLOBAL',$key);
				next FILLUPHASH;
			}
		}
		$returningoptions{$key} = ${$default{$key}}[0];
	}

	if( $returningoptions{help} )
	{
		delete $default{help} if $currentpackagename ne 'main' ;
		warn "[$packagename] module options are :\n",join("\t\n",map(sprintf("--%-30s default: %s%s",$_.' ('.${$default{$_}}[-1].')',${$default{$_}}[0],($returningoptions{$_} ne ${$default{$_}}[0]?sprintf("\n%-32s current: %s",'',$returningoptions{$_}):'')),sort keys %default))."\n";
		exit if $currentpackagename eq 'main' ;
	}
	return %returningoptions;
}

1;
