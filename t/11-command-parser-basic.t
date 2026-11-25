#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['block C-z', { cmd => 'block', keys => ["\x1a"] }],
	['block a', { cmd => 'block', keys => ['a'] }],
	['block C-z C-c Up', { cmd => 'block', keys => ["\x1a", "\x03", "\e[A"] }],
	['  block   C-z  ', { cmd => 'block', keys => ["\x1a"] }],
	["block C-z\n", { cmd => 'block', keys => ["\x1a"] }],
	["block C-z\r\n", { cmd => 'block', keys => ["\x1a"] }],
	['unblock C-z', { cmd => 'unblock', keys => ["\x1a"] }],
	['unblock a b', { cmd => 'unblock', keys => ['a', 'b'] }],
	['map a=b', { cmd => 'map', key => 'a', replacement => 'b' }],
	['map F1=git status\n', { cmd => 'map', key => "\eOP", replacement => "git status\n" }],
	['map F1=<<Enter>>', { cmd => 'map', key => "\eOP", replacement => "\r" }],
	['map F1=abc<<Enter>><<C-a>>', { cmd => 'map', key => "\eOP", replacement => "abc\r\x01" }],
	['map M-b=<<C-t>>', { cmd => 'map', key => "\eb", replacement => "\x14" }],
	['map ==x', { cmd => 'map', key => '=', replacement => 'x' }],
	['map a==', { cmd => 'map', key => 'a', replacement => '=' }],
	['map a=', { cmd => 'map', key => 'a', replacement => '' }],
	['map a=b c ', { cmd => 'map', key => 'a', replacement => 'b c ' }],
	['block C-z # comment', { cmd => 'block', keys => ["\x1a"] }],
	['block C-z#comment', { cmd => 'block', keys => ["\x1a"] }],
	['block \#', { cmd => 'block', keys => ['#'] }],
	['block a \# b', { cmd => 'block', keys => ['a', '#', 'b'] }],
	['map a=b # comment', { cmd => 'map', key => 'a', replacement => 'b' }],
	['map a=b#comment', { cmd => 'map', key => 'a', replacement => 'b' }],
	['map a=b\#c', { cmd => 'map', key => 'a', replacement => 'b#c' }],
	['map a=<<\#>>', { cmd => 'map', key => 'a', replacement => '#' }],
	['map a=b\x20 # comment', { cmd => 'map', key => 'a', replacement => 'b ' }],
	['map a=\\\\# comment', { cmd => 'map', key => 'a', replacement => '\\' }],
	) ;

for my $case (@cases)
	{
	my ($line, $expected) = @$case ;
	
	is_deeply(scalar KeyFilter::Command::parse_command($line), $expected, $line) ;
	}

my @ignored = ('', '   ', "\n", '# comment', '   # indented comment', '#block C-z', '#', '##', '  #') ;

for my $line (@ignored)
	{
	is_deeply([ KeyFilter::Command::parse_command($line) ], [], "ignored line '$line'") ;
	}

my @errors =
	(
	['frobnicate x', qr/unknown command 'frobnicate'/],
	['Block C-z', qr/unknown command 'Block'/],
	['block', qr/block requires at least one key specification/],
	['unblock', qr/unblock requires at least one key specification/],
	['block # nothing', qr/block requires at least one key specification/],
	['map a # nothing', qr/invalid syntax/],
	['block bogus', qr/unknown key specification 'bogus'/],
	['block C-z bogus', qr/unknown key specification 'bogus'/],
	['map', qr/invalid syntax, expected: map KEY=REPLACEMENT/],
	['map a', qr/invalid syntax/],
	['map =b', qr/invalid syntax/],
	['map a = b', qr/invalid syntax/],
	['map bogus=x', qr/unknown key specification 'bogus'/],
	['map a=<<bogus>>', qr/unknown key specification 'bogus'/],
	['map a=<<Enter', qr/unterminated key symbol/],
	['map a=\q', qr/unknown escape/],
	) ;

for my $case (@errors)
	{
	my ($line, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Command::parse_command($line) ; }), $pattern, "error for '$line'") ;
	}

done_testing ;
