#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['send abc', { cmd => 'send', text => 'abc' }],
	['send abc<<Enter>>', { cmd => 'send', text => "abc\r" }],
	['send <<C-c>>', { cmd => 'send', text => "\x03" }],
	['send git status\n', { cmd => 'send', text => "git status\n" }],
	['send hello world ', { cmd => 'send', text => 'hello world ' }],
	['send <<Up>><<Up>><<Enter>>', { cmd => 'send', text => "\e[A\e[A\r" }],
	['send a<<M-b>>c', { cmd => 'send', text => "a\ebc" }],
	["send abc<<Enter>>\n", { cmd => 'send', text => "abc\r" }],
	) ;

for my $case (@cases)
	{
	my ($line, $expected) = @$case ;
	
	is_deeply(scalar KeyFilter::Command::parse_command($line), $expected, $line) ;
	}

my @errors =
	(
	['send', qr/send requires text/],
	['send   ', qr/send requires text/],
	['send <<bogus>>', qr/unknown key specification 'bogus'/],
	['send abc<<Enter', qr/unterminated key symbol/],
	['send a\q', qr/unknown escape/],
	) ;

for my $case (@errors)
	{
	my ($line, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Command::parse_command($line) ; }), $pattern, "error for '$line'") ;
	}

done_testing ;
