#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;

require "$FindBin::Bin/../keyfilter" ;

my @packages =
	(
	'KeyFilter::Key',
	'KeyFilter::Replacement',
	'KeyFilter::Command',
	'KeyFilter::Rules',
	'KeyFilter::Profile',
	'KeyFilter::Chain',
	'KeyFilter::PTY',
	'KeyFilter::Discovery',
	'KeyFilter::Startup',
	'KeyFilter::Recorder',
	'KeyFilter::Replayer',
	'KeyFilter::Control',
	'KeyFilter::Ctl',
	'KeyFilter::CLI',
	) ;

for my $package (@packages)
	{
	no strict 'refs' ;
	
	ok(defined ${"${package}::VERSION"}, "$package is defined") ;
	}

ok(KeyFilter::CLI->can('main'), 'KeyFilter::CLI::main exists') ;

done_testing ;
