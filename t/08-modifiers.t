#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my %expected =
	(
	'M-a'       => "\ea",
	'M-A'       => "\eA",
	'M-\#'      => "\e#",
	'S-a'       => 'A',
	'M-S-a'     => "\eA",
	'C-M-a'     => "\e\x01",
	'C-S-a'     => "\x01",
	'M-Enter'   => "\e\r",
	'M-Esc'     => "\e\e",
	'S-Tab'     => "\e[Z",
	'M-Tab'     => "\e\t",
	'M-S-Tab'   => "\e\e[Z",
	'C-Space'   => "\x00",
	'C-M-Space' => "\e\x00",
	'S-Up'      => "\e[1;2A",
	'M-Up'      => "\e[1;3A",
	'C-Up'      => "\e[1;5A",
	'C-M-S-Up'  => "\e[1;8A",
	'C-Delete'  => "\e[3;5~",
	'S-F1'      => "\e[1;2P",
	'C-F4'      => "\e[1;5S",
	'M-F5'      => "\e[15;3~",
	'C-M-S-F5'  => "\e[15;8~",
	) ;

for my $spec (sort keys %expected)
	{
	is(KeyFilter::Key::parse_key($spec), $expected{$spec}, $spec) ;
	}

my @orders = ('C-M-S-F5', 'C-S-M-F5', 'M-C-S-F5', 'M-S-C-F5', 'S-C-M-F5', 'S-M-C-F5') ;

for my $spec (@orders)
	{
	is(KeyFilter::Key::parse_key($spec), "\e[15;8~", "$spec, order does not matter") ;
	}

is(KeyFilter::Key::parse_key('C-M-a'), KeyFilter::Key::parse_key('M-C-a'), 'C-M-a and M-C-a are equivalent') ;
is(KeyFilter::Key::parse_key('M-S-a'), KeyFilter::Key::parse_key('S-M-a'), 'M-S-a and S-M-a are equivalent') ;
is(KeyFilter::Key::parse_key('-'), '-', 'minus is a key') ;
is(KeyFilter::Key::parse_key('M--'), "\e-", 'M-- is Alt minus') ;
is(KeyFilter::Key::parse_key('C-M-S'), "\e\x13", 'S is a key after modifiers') ;
is_deeply([ KeyFilter::Key::parse_key_specs('M-a C-Up b') ], ["\ea", "\e[1;5A", 'b'], 'modified keys in a list') ;

my @errors =
	(
	['C-C-a', qr/duplicate modifier 'C' in key specification 'C-C-a'/],
	['M-a-M-a', qr/unknown key specification 'M-a-M-a'/],
	['S-1', qr/modifier S needs a letter/],
	['C-1', qr/has no control character/],
	['C-Enter', qr/modifier C is not supported for key specification 'C-Enter'/],
	['S-Space', qr/modifier S is not supported/],
	['X-a', qr/unknown key specification 'X-a'/],
	['M-', qr/unknown key specification 'M-'/],
	['M-bogus', qr/unknown key specification 'M-bogus'/],
	['M-C-', qr/unknown key specification 'M-C-'/],
	) ;

for my $case (@errors)
	{
	my ($spec, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Key::parse_key($spec) ; }), $pattern, "error for '$spec'") ;
	}

done_testing ;
