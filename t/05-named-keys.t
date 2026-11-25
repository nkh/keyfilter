#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my %expected =
	(
	Enter     => "\r",
	Return    => "\r",
	Tab       => "\t",
	Esc       => "\e",
	Escape    => "\e",
	Space     => ' ',
	Backspace => "\x7f",
	) ;

for my $name (sort keys %expected)
	{
	is(KeyFilter::Key::parse_key($name), $expected{$name}, $name) ;
	}

is_deeply([ KeyFilter::Key::parse_key_specs('Enter Tab Esc') ], ["\r", "\t", "\e"], 'named keys in a list') ;
is_deeply([ KeyFilter::Key::parse_key_specs('a Space b') ], ['a', ' ', 'b'], 'Space separates keys in a list') ;

like(failure_of(sub { KeyFilter::Key::parse_key('enter') ; }), qr/unknown key specification 'enter'/, 'names are case sensitive') ;
like(failure_of(sub { KeyFilter::Key::parse_key('Entr') ; }), qr/unknown key specification 'Entr'/, 'misspelled name') ;

done_testing ;
