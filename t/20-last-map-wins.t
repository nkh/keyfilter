#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	[['map a=b', 'map a=c'], 'a', 'c', 'the second map wins'],
	[['map a=b', 'map a=c', 'map a=d'], 'a', 'd', 'the third map wins'],
	[['map a=c', 'map a=b'], 'a', 'b', 'declaration order decides, not the value'],
	[['map a=b', 'block a', 'unblock a', 'map a=c'], 'a', 'c', 'block and unblock in between change nothing'],
	[['map a=b', 'map a='], 'a', '', 'an empty replacement is a replacement'],
	[['map a=b', 'map a=a'], 'a', 'a', 'a map to the key itself still wins'],
	[['map a=b', 'map c=d', 'map a=e'], 'a', 'e', 'maps for other keys in between'],
	[['map a=b', 'map c=d', 'map a=e'], 'c', 'd', 'and they keep their own map'],
	[['map a=x', 'map a=<<Enter>>'], 'a', "\r", 'a replacement with a key symbol wins'],
	[['map F1=a', 'map F1=b<<Enter>>'], "\eOP", "b\r", 'it works for sequences'],
	) ;

for my $case (@cases)
	{
	my ($lines, $key, $expected, $name) = @$case ;
	
	is(rules_from(@$lines)->process($key), $expected, $name) ;
	}

my $rules = rules_from('map a=b', 'map a=c') ;

is_deeply($rules->evaluate('a'), { blocked => 0, replacement => 'c' }, 'evaluate reports the last map') ;
is_deeply($rules->evaluate('z'), { blocked => 0, replacement => undef }, 'evaluate reports no map for z') ;
is_deeply(rules_from('block a', 'map a=b')->evaluate('a'), { blocked => 1, replacement => 'b' }, 'evaluate reports block and map') ;
is_deeply(rules_from('map a=')->evaluate('a'), { blocked => 0, replacement => '' }, 'evaluate keeps an empty replacement') ;
is_deeply(rules_from('block a', 'unblock a')->evaluate('a'), { blocked => 0, replacement => undef }, 'evaluate reports an unblocked key') ;

done_testing ;
