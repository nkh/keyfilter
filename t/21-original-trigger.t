#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $chain = rules_from('map a=b', 'map b=c') ;

is($chain->process('a'), 'b', 'a produces b, not c, transforms never chain') ;
is($chain->process('b'), 'c', 'b produces c') ;
is($chain->process_keys('a', 'b'), 'bc', 'each key is evaluated on its own') ;
is($chain->process_keys('b', 'a'), 'cb', 'in any order') ;
is($chain->process_keys('a', 'a', 'a'), 'bbb', 'the same key gives the same result each time') ;

my $swap = rules_from('map a=b', 'map b=a') ;

is($swap->process('a'), 'b', 'a and b can be swapped, a becomes b') ;
is($swap->process('b'), 'a', 'and b becomes a') ;
is($swap->process_keys('a', 'b'), 'ba', 'the swap does not loop') ;

my $blocked_target = rules_from('map a=b', 'block b') ;

is($blocked_target->process('a'), 'b', 'blocking b does not block what a produces') ;
is($blocked_target->process('b'), '', 'but typing b is blocked') ;

my $recursive = rules_from('map F1=aaa', 'map a=b') ;

is($recursive->process("\eOP"), 'aaa', 'a replacement is not mapped again') ;
is($recursive->process('a'), 'b', 'while typing a is mapped') ;

my $enter = rules_from('map a=<<Enter>>', 'block Enter') ;

is($enter->process('a'), "\r", 'a replacement is not blocked') ;
is($enter->process("\r"), '', 'while typing Enter is blocked') ;

my $self_map = rules_from('map a=aa') ;

is($self_map->process('a'), 'aa', 'a map to itself is applied once') ;

my $mixed = rules_from('map a=x', 'block z', 'map c=y') ;

is($mixed->process_keys('a', 'z', 'b', 'c'), 'xby', 'blocked keys vanish, others are mapped or pass') ;
is($mixed->process_keys(), '', 'no keys give no output') ;
is(KeyFilter::Rules->new()->process_keys('a', 'b'), 'ab', 'without rules the keys pass') ;

done_testing ;
