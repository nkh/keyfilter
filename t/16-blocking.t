#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $rules = rules_from('block a') ;

is($rules->process('a'), '', 'a is blocked') ;
is($rules->process('b'), 'b', 'b is not blocked') ;
is($rules->process('A'), 'A', 'blocking is case sensitive') ;
ok(defined $rules->process('a'), 'a blocked key gives an empty string, not undef') ;

my $several_keys = rules_from('block C-z C-c Up') ;

is($several_keys->process("\x1a"), '', 'C-z is blocked') ;
is($several_keys->process("\x03"), '', 'C-c is blocked') ;
is($several_keys->process("\e[A"), '', 'Up is blocked') ;
is($several_keys->process("\e[B"), "\e[B", 'Down is not blocked') ;
is($several_keys->process('z'), 'z', 'z is not C-z') ;

my $several_rules = rules_from('block a', 'block b') ;

is($several_rules->process('a'), '', 'a is blocked by the first rule') ;
is($several_rules->process('b'), '', 'b is blocked by the second rule') ;
is($several_rules->process('c'), 'c', 'c is not blocked') ;

my $sequences = rules_from('block 1b5b41', 'block M-a') ;

is($sequences->process("\e[A"), '', 'a raw sequence is blocked') ;
is($sequences->process("\ea"), '', 'M-a is blocked') ;
is($sequences->process('a'), 'a', 'a is not M-a') ;

my $empty = KeyFilter::Rules->new() ;

is($empty->process('a'), 'a', 'without rules every key passes') ;
is($empty->process("\e[A"), "\e[A", 'without rules a sequence passes') ;

done_testing ;
