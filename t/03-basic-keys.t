#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @singles = ('a', 'z', 'A', 'Z', '0', '9', '!', '-', '=', '~', '/', '\\') ;

for my $key (@singles)
	{
	is(KeyFilter::Key::parse_key($key), $key, "key '$key'") ;
	}

is_deeply([ KeyFilter::Key::parse_key_specs('a b C') ], ['a', 'b', 'C'], 'several specs') ;
is_deeply([ KeyFilter::Key::parse_key_specs('  a   b  ') ], ['a', 'b'], 'extra whitespace is ignored') ;
is_deeply([ KeyFilter::Key::parse_key_specs('') ], [], 'empty text gives no keys') ;

is(KeyFilter::Key::parse_key('\#'), '#', 'escaped hash is the hash key') ;

like(failure_of(sub { KeyFilter::Key::parse_key('bogus') ; }), qr/unknown key specification 'bogus'/, 'unknown spec') ;
like(failure_of(sub { KeyFilter::Key::parse_key('') ; }), qr/unknown key specification ''/, 'empty spec') ;
like(failure_of(sub { KeyFilter::Key::parse_key(' ') ; }), qr/unknown key specification ' '/, 'space is not a basic key') ;
like(failure_of(sub { KeyFilter::Key::parse_key_specs('a bogus') ; }), qr/'bogus'/, 'error in a list names the spec') ;

done_testing ;
