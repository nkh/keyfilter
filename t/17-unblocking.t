#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	[['block a', 'unblock a'], 'a', 'a', 'unblock re-enables a blocked key'],
	[['unblock a', 'block a'], 'a', '', 'declaration order decides, block after unblock'],
	[['unblock a'], 'a', 'a', 'unblock without block does nothing'],
	[['block a', 'unblock a', 'block a'], 'a', '', 'a key can be blocked again'],
	[['block a', 'unblock a', 'block a', 'unblock a'], 'a', 'a', 'and unblocked again'],
	[['block a b', 'unblock a'], 'a', 'a', 'unblock a leaves a free'],
	[['block a b', 'unblock a'], 'b', '', 'unblock a leaves b blocked'],
	[['block a b c', 'unblock a c'], 'c', 'c', 'unblock takes several keys'],
	[['block a b c', 'unblock a c'], 'b', '', 'and keeps the others blocked'],
	[['block a', 'unblock b'], 'a', '', 'unblock of another key changes nothing'],
	[['block C-z', 'unblock C-z'], "\x1a", "\x1a", 'unblock works on control keys'],
	[['block Up', 'unblock Up'], "\e[A", "\e[A", 'unblock works on sequences'],
	[['block a', 'unblock A'], 'a', '', 'unblocking is case sensitive'],
	) ;

for my $case (@cases)
	{
	my ($lines, $key, $expected, $name) = @$case ;
	
	is(rules_from(@$lines)->process($key), $expected, $name) ;
	}

done_testing ;
