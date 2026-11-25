#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my %expected =
	(
	'1b5b41'           => "\e[A",
	'1B5B41'           => "\e[A",
	'1b5b4a'           => "\e[J",
	'0a'               => "\n",
	'ff'               => "\xff",
	'00'               => "\x00",
	'\x1b\x5b\x41'     => "\e[A",
	'\x1B\x5B\x41'     => "\e[A",
	'\x0a'             => "\n",
	'\x61'             => 'a',
	) ;

for my $spec (sort keys %expected)
	{
	is(KeyFilter::Key::parse_key($spec), $expected{$spec}, $spec) ;
	}

is(KeyFilter::Key::parse_key('F1'), "\eOP", 'F1 is the key, not a raw byte') ;
is(KeyFilter::Key::parse_key('f1'), "\xf1", 'f1 is a raw byte') ;
is_deeply([ KeyFilter::Key::parse_key_specs('1b5b41 a \x1b\x5b\x42') ], ["\e[A", 'a', "\e[B"], 'raw sequences in a list') ;

my @errors =
	(
	'abc',
	'1b5',
	'zz',
	'\x1',
	'\x1b5b',
	'1b\x5b',
	'\x1g',
	'C-1b',
	'M-\x1b',
	) ;

for my $spec (@errors)
	{
	like(failure_of(sub { KeyFilter::Key::parse_key($spec) ; }), qr/unknown key specification '\Q$spec\E'/, "error for '$spec'") ;
	}

done_testing ;
