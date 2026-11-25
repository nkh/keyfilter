#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

for my $letter ('a' .. 'z')
	{
	my $upper    = uc $letter ;
	my $expected = chr(ord($letter) - ord('a') + 1) ;
	
	is(KeyFilter::Key::parse_key("C-$letter"), $expected, "C-$letter") ;
	is(KeyFilter::Key::parse_key("C-$upper"), $expected, "C-$upper is the same as C-$letter") ;
	}

my %punctuation =
	(
	'C-@'  => "\x00",
	'C-['  => "\x1b",
	'C-\\' => "\x1c",
	'C-]'  => "\x1d",
	'C-^'  => "\x1e",
	'C-_'  => "\x1f",
	'C-?'  => "\x7f",
	) ;

for my $spec (sort keys %punctuation)
	{
	is(KeyFilter::Key::parse_key($spec), $punctuation{$spec}, $spec) ;
	}

is(KeyFilter::Key::parse_key('C-i'), "\t", 'C-i is Tab') ;
is(KeyFilter::Key::parse_key('C-m'), "\r", 'C-m is Enter') ;
is(KeyFilter::Key::parse_key('C-['), "\e", 'C-[ is Esc') ;
is_deeply([ KeyFilter::Key::parse_key_specs('C-a C-z b') ], ["\x01", "\x1a", 'b'], 'control keys in a list') ;

like(failure_of(sub { KeyFilter::Key::parse_key('C-1') ; }), qr/'C-1' has no control character/, 'digit has no control character') ;
like(failure_of(sub { KeyFilter::Key::parse_key('C-') ; }), qr/unknown key specification 'C-'/, 'missing key') ;
like(failure_of(sub { KeyFilter::Key::parse_key('C-ab') ; }), qr/unknown key specification 'C-ab'/, 'two keys after C-') ;

done_testing ;
