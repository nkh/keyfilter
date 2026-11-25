#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my %expected =
	(
	F1  => "\eOP",
	F2  => "\eOQ",
	F3  => "\eOR",
	F4  => "\eOS",
	F5  => "\e[15~",
	F6  => "\e[17~",
	F7  => "\e[18~",
	F8  => "\e[19~",
	F9  => "\e[20~",
	F10 => "\e[21~",
	F11 => "\e[23~",
	F12 => "\e[24~",
	) ;

for my $name (sort keys %expected)
	{
	is(KeyFilter::Key::parse_key($name), $expected{$name}, $name) ;
	}

is_deeply([ KeyFilter::Key::parse_key_specs('F1 F12') ], ["\eOP", "\e[24~"], 'function keys in a list') ;

like(failure_of(sub { KeyFilter::Key::parse_key('F13') ; }), qr/unknown key specification 'F13'/, 'F13 is not defined') ;
like(failure_of(sub { KeyFilter::Key::parse_key('F99') ; }), qr/unknown key specification 'F99'/, 'F99 is not defined') ;
like(failure_of(sub { KeyFilter::Key::parse_key('fn1') ; }), qr/unknown key specification 'fn1'/, 'names are case sensitive') ;

done_testing ;
