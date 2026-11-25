#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $rules = KeyFilter::Rules->new() ;

is($rules->count, 0, 'a new store is empty') ;
is_deeply([ $rules->rules ], [], 'a new store has no rules') ;

my @lines    = ('block C-z', 'map a=b', 'unblock C-z', 'map F1=<<Enter>>') ;
my @commands = map { scalar KeyFilter::Command::parse_command($_) } @lines ;

$rules->add($_) for @commands ;

is($rules->count, 4, 'four rules are stored') ;
is_deeply([ $rules->rules ], \@commands, 'rules are returned in declaration order') ;
is_deeply([ map { $_->{cmd} } $rules->rules ], ['block', 'map', 'unblock', 'map'], 'command names keep their order') ;
is(($rules->rules)[1], $commands[1], 'the stored command is the command that was added') ;

$rules->add($commands[0]) ;

is($rules->count, 5, 'the same command can be stored twice') ;
is_deeply([ map { $_->{cmd} } $rules->rules ], ['block', 'map', 'unblock', 'map', 'block'], 'a duplicate is appended') ;

my $chained = KeyFilter::Rules->new()->add($commands[0])->add($commands[1]) ;

isa_ok($chained, 'KeyFilter::Rules') ;
is($chained->count, 2, 'add can be chained') ;
is($rules->count, 5, 'stores are independent') ;

my @rejected =
	(
	['send abc', 'send'],
	['toggle gaming', 'toggle'],
	['include common.profile', 'include'],
	['profile vim', 'profile'],
	['startup-delay 500', 'startup-delay'],
	['send-startup make\n', 'send-startup'],
	) ;

for my $case (@rejected)
	{
	my ($line, $name) = @$case ;
	
	my $command = scalar KeyFilter::Command::parse_command($line) ;
	
	like(failure_of(sub { $rules->add($command) ; }), qr/not a rule command '$name'/, "$name is not a rule") ;
	}

like(failure_of(sub { $rules->add('block a') ; }), qr/not a rule command ''/, 'text is not a rule') ;
like(failure_of(sub { $rules->add(undef) ; }), qr/not a rule command ''/, 'undef is not a rule') ;
like(failure_of(sub { $rules->add({}) ; }), qr/not a rule command ''/, 'an empty hash is not a rule') ;
like(failure_of(sub { $rules->add({ cmd => 'frobnicate' }) ; }), qr/not a rule command 'frobnicate'/, 'an unknown command is not a rule') ;

is($rules->count, 5, 'rejected commands are not stored') ;

is($rules->clear, $rules, 'clear returns the store') ;
is($rules->count, 0, 'clear empties the store') ;
is_deeply([ $rules->rules ], [], 'a cleared store has no rules') ;

done_testing ;
