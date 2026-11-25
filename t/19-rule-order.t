#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $rules = rules_from('block a', 'map b=x', 'map a=c', 'unblock a', 'map a=d', 'block b') ;

is_deeply([ map { $_->{cmd} } $rules->matching_rules('a') ], ['block', 'map', 'unblock', 'map'], 'every rule matching a, in declaration order') ;
is_deeply([ map { $_->{cmd} } $rules->matching_rules('b') ], ['map', 'block'], 'every rule matching b, in declaration order') ;
is_deeply([ map { $_->{replacement} } grep { $_->{cmd} eq 'map' } $rules->matching_rules('a') ], ['c', 'd'], 'maps for a keep their order') ;
is_deeply([ $rules->matching_rules('z') ], [], 'no rule matches z') ;
is_deeply([ KeyFilter::Rules->new()->matching_rules('a') ], [], 'an empty store has no matching rule') ;

my @cases =
	(
	[['block a', 'map a=b', 'unblock a'], 'a', 'b', 'the blocking example of the requirements'],
	[['block a', 'map a=b', 'unblock a'], 'z', 'z', 'other keys are not affected'],
	[['map a=b', 'block a'], 'a', '', 'blocked when evaluation ends'],
	[['block a', 'map a=b'], 'a', '', 'a map does not unblock'],
	[['block a', 'unblock a'], 'a', 'a', 'both rules are evaluated, not only the first'],
	[['unblock a', 'block a'], 'a', '', 'declaration order decides'],
	[['block a', 'unblock a', 'block a', 'map a=x'], 'a', '', 'the last block wins over the map'],
	[['block a', 'map a=b', 'unblock a', 'block a'], 'a', '', 'block after unblock'],
	[['map a=b', 'block a', 'unblock a'], 'a', 'b', 'a map before block and unblock still applies'],
	[['block a', 'unblock a', 'map a=b'], 'a', 'b', 'a map after block and unblock applies'],
	[['block a b', 'map a=x', 'unblock b'], 'b', 'b', 'rules with several keys are all evaluated'],
	[['block a b', 'map a=x', 'unblock b'], 'a', '', 'and a stays blocked'],
	) ;

for my $case (@cases)
	{
	my ($lines, $key, $expected, $name) = @$case ;
	
	is(rules_from(@$lines)->process($key), $expected, $name) ;
	}

done_testing ;
