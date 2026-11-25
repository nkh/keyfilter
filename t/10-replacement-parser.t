#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['b', 'b'],
	['', ''],
	['abc', 'abc'],
	['git status', 'git status'],
	['git status\n', "git status\n"],
	['<<Enter>>', "\r"],
	['<<C-a>>', "\x01"],
	['<<Up>>', "\e[A"],
	['<<F5>>', "\e[15~"],
	['<<M-a>>', "\ea"],
	['abc<<Enter>><<C-a>>', "abc\r\x01"],
	['ls<<Space>>-l<<Enter>>', "ls -l\r"],
	['a\tb', "a\tb"],
	['a\rb', "a\rb"],
	['\e[A', "\e[A"],
	['\\\\', '\\'],
	['\x41\x62', 'Ab'],
	['\x1b[B', "\e[B"],
	['\<\<', '<<'],
	['\<<Enter>>', '<<Enter>>'],
	['a < b > c', 'a < b > c'],
	['<a>', '<a>'],
	['a\#b', 'a#b'],
	['<<\#>>', '#'],
	['<<a>><<b>>', 'ab'],
	['x<<1b5b41>>y', "x\e[Ay"],
	) ;

for my $case (@cases)
	{
	my ($text, $expected) = @$case ;
	
	is(KeyFilter::Replacement::parse_replacement($text), $expected, "replacement '$text'") ;
	}

my @errors =
	(
	['<<Enter', qr/unterminated key symbol in replacement '<<Enter'/],
	['abc<<', qr/unterminated key symbol/],
	['<<bogus>>', qr/unknown key specification 'bogus'/],
	['<<>>', qr/unknown key specification ''/],
	['a\qb', qr/unknown escape '\\q' in replacement 'a\\qb'/],
	['abc\\', qr/trailing backslash in replacement 'abc\\'/],
	['\x1', qr/unknown escape '\\x'/],
	) ;

for my $case (@errors)
	{
	my ($text, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Replacement::parse_replacement($text) ; }), $pattern, "error for '$text'") ;
	}

done_testing ;
