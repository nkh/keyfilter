#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my %expected =
	(
	Up       => "\e[A",
	Down     => "\e[B",
	Right    => "\e[C",
	Left     => "\e[D",
	Home     => "\e[H",
	End      => "\e[F",
	Insert   => "\e[2~",
	Delete   => "\e[3~",
	PgUp     => "\e[5~",
	PgDn     => "\e[6~",
	PageUp   => "\e[5~",
	PageDown => "\e[6~",
	) ;

for my $name (sort keys %expected)
	{
	is(KeyFilter::Key::parse_key($name), $expected{$name}, $name) ;
	}

is(KeyFilter::Key::parse_key('Up'), "\x1b\x5b\x41", 'Up is 1b 5b 41') ;
is_deeply([ KeyFilter::Key::parse_key_specs('Up Down a') ], ["\e[A", "\e[B", 'a'], 'navigation keys in a list') ;

like(failure_of(sub { KeyFilter::Key::parse_key('up') ; }), qr/unknown key specification 'up'/, 'names are case sensitive') ;

done_testing ;
