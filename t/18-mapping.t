#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['map a=b', 'a', 'b'],
	['map a=b', 'c', 'c'],
	['map a=b', 'b', 'b'],
	['map a=b', 'A', 'A'],
	['map a=', 'a', ''],
	['map a=a', 'a', 'a'],
	['map a=ab', 'a', 'ab'],
	['map F1=<<Enter>>', "\eOP", "\r"],
	['map F1=<<Enter>>', "\eOQ", "\eOQ"],
	['map F1=git status\n', "\eOP", "git status\n"],
	['map F1=abc<<Enter>><<C-a>>', "\eOP", "abc\r\x01"],
	['map C-a=<<Up>>', "\x01", "\e[A"],
	['map C-a=<<Up>>', 'a', 'a'],
	['map M-b=x', "\eb", 'x'],
	['map M-b=x', 'b', 'b'],
	['map Up=<<Down>>', "\e[A", "\e[B"],
	['map Up=<<Down>>', "\e[B", "\e[B"],
	['map 1b5b41=up', "\e[A", 'up'],
	) ;

for my $case (@cases)
	{
	my ($line, $key, $expected) = @$case ;
	
	is(rules_from($line)->process($key), $expected, "$line, key " . unpack('H*', $key)) ;
	}

my $several = rules_from('map a=1', 'map b=2') ;

is($several->process('a'), '1', 'first map applies to a') ;
is($several->process('b'), '2', 'second map applies to b') ;
is($several->process('c'), 'c', 'c has no map') ;

my $mixed = rules_from('block z', 'map a=b', 'unblock z') ;

is($mixed->process('a'), 'b', 'maps work next to block rules') ;
is($mixed->process('z'), 'z', 'and unblocked keys pass') ;

done_testing ;
