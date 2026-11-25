#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use IO::Socket::UNIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $home = temp_dir() ;
my $dir  = temp_dir() ;

local $ENV{HOME} = "$home" ;

my $profiles = "$home/.config/keyfilter" ;

sub parsed { return map { scalar KeyFilter::Command::parse_command($_) } @_ ; }

# -----------------------------------------------------------------------------

sub profile_file
{
my ($name, @lines) = @_ ;

write_file("$profiles/$name.profile", map { "$_\n" } @lines) ;

return "$profiles/$name.profile" ;
}

# -----------------------------------------------------------------------------

sub chain_of
{
my (@names) = @_ ;

return KeyFilter::Chain->new(profiles => [ map { KeyFilter::Profile::load("$profiles/$_.profile") } @names ]) ;
}

# -----------------------------------------------------------------------------

profile_file('a', 'map x=1', 'map a=a') ;
profile_file('b', 'map x=2', 'map b=b') ;
profile_file('c', 'map x=3', 'map c=c') ;
profile_file('d', 'map x=4', 'map d=d') ;
profile_file('e', 'map x=5') ;

# a profile comes back where it was

my $chain = chain_of('a', 'b', 'c') ;

$chain->disable('b') ;

is_deeply([ $chain->active_names ], ['a', 'c'], 'a disabled profile leaves a gap') ;

$chain->enable('b') ;

is_deeply([ $chain->active_names ], ['a', 'b', 'c'], 'and when it is enabled again it is back in the middle') ;
is($chain->rules->process('x'), '3', 'the last profile still wins') ;

$chain->disable('a') ;
$chain->enable('a') ;

is_deeply([ $chain->active_names ], ['a', 'b', 'c'], 'the first one comes back first') ;
is($chain->rules->process('x'), '3', 'without taking over from the others') ;

$chain->disable('c') ;
$chain->enable('c') ;

is_deeply([ $chain->active_names ], ['a', 'b', 'c'], 'and the last one last') ;

$chain->disable($_) for 'a', 'b', 'c' ;
$chain->enable($_) for 'c', 'b', 'a' ;

is_deeply([ $chain->active_names ], ['a', 'b', 'c'], 'whatever the order they are enabled in') ;
is($chain->rules->process('x'), '3', 'the order of the rules is the order of the chain') ;

$chain->disable('c') ;

is($chain->rules->process('x'), '2', 'with the last one off the one before wins') ;

$chain->disable('b') ;
$chain->enable('a') ;
$chain->enable('b') ;

is($chain->rules->process('x'), '2', 'enabling an earlier profile after a later one does not give it the last word') ;

$chain->enable('c') ;

is($chain->rules->process('x'), '3', 'the last one has it again') ;
is_deeply([ $chain->profile_names ], ['a', 'b', 'c'], 'toggling never changes the list of profiles') ;
is_deeply([ $chain->order ], ['a', 'b', 'c', 'keyfilter_command_line', 'keyfilter_runtime'], 'and the order shows it') ;

# profiles that were loaded later

my $growing = chain_of('a', 'b') ;

$growing->enable('c') ;
$growing->enable('d') ;

is_deeply([ $growing->profile_names ], ['a', 'b', 'c', 'd'], 'a profile loaded when it is enabled is added at the end') ;

$growing->disable('c') ;
$growing->enable('e') ;

is_deeply([ $growing->active_names ], ['a', 'b', 'd', 'e'], 'a gap is not filled by a profile loaded later') ;

$growing->enable('c') ;

is_deeply([ $growing->active_names ], ['a', 'b', 'c', 'd', 'e'], 'it is where it was added when it comes back') ;
is($growing->rules->process('x'), '5', 'and the last one wins') ;

$growing->disable('d') ;
$growing->disable('b') ;
$growing->enable('d') ;
$growing->enable('b') ;

is_deeply([ $growing->active_names ], ['a', 'b', 'c', 'd', 'e'], 'also for several gaps') ;

# the other layers stay last

my $layers = KeyFilter::Chain->new(profiles => [ map { KeyFilter::Profile::load("$profiles/$_.profile") } 'a', 'b' ], command_line => [ parsed('map x=cl') ]) ;

$layers->add_runtime($_) for parsed('map a=rt') ;
$layers->disable('a') ;
$layers->enable('a') ;

is_deeply([ $layers->order ], ['a', 'b', 'keyfilter_command_line', 'keyfilter_runtime'], 'the command line and the runtime profile stay after the profiles') ;
is($layers->rules->process('x'), 'cl', 'and win over them') ;
is($layers->rules->process('a'), 'rt', 'also over a profile that came back') ;

# any sequence of toggles gives the order of the chain

srand(2026) ;

my @names  = ('a', 'b', 'c', 'd', 'e') ;
my %active = map { $_ => 1 } @names ;
my $random = chain_of(@names) ;
my $wrong  = 0 ;

for (1 .. 400)
	{
	my $name   = $names[int rand @names] ;
	my $action = int rand 3 ;
	
	if ($action == 0)
		{
		$random->enable($name) ;
		
		$active{$name} = 1 ;
		}
	elsif ($action == 1)
		{
		$random->disable($name) ;
		
		delete $active{$name} ;
		}
	else
		{
		$random->toggle($name) ;
		
		$active{$name} ? delete $active{$name} : ($active{$name} = 1) ;
		}
	
	my @expected = grep { $active{$_} } @names ;
	my ($last)   = reverse @expected ;
	my %winner   = (a => 1, b => 2, c => 3, d => 4, e => 5) ;
	
	$wrong++ unless join(',', $random->active_names) eq join(',', @expected) && $random->rules->process('x') eq (defined $last ? $winner{$last} : 'x') ;
	}

is($wrong, 0, 'four hundred random toggles always give the active profiles in the order of the chain') ;

# in a running engine

my $counter = 0 ;
my @writers ;

sub rig
{
my (%options) = @_ ;

my $name = 'case' . ++$counter ;

my ($input, $writer) = pipe_pair() ;

push @writers, $writer ;

my $pty = start_engine({ input => $input, chain => $options{chain} }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/$name.ready ; head -c $options{bytes} > $dir/$name.out") ;

die "the child is not ready\n" unless wait_for_file("$dir/$name.ready") ;

return { pty => $pty, writer => $writer, input => $input, chain => $options{chain}, out => "$dir/$name.out" } ;
}

# -----------------------------------------------------------------------------

sub type
{
my ($rig, $bytes) = @_ ;

syswrite($rig->{writer}, $bytes) ;

my $deadline = Time::HiRes::time() + 20 ;

while (Time::HiRes::time() < $deadline)
	{
	return 1 if !IO::Select->new($rig->{input})->can_read(0) && !$rig->{pty}->pending_input && !defined $rig->{pty}->key_remaining ;
	
	$rig->{pty}->pump(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

sub received { my ($rig) = @_ ; $rig->{pty}->wait_exit ; return read_file($rig->{out}) ; }

# -----------------------------------------------------------------------------

my $engine = rig(chain => chain_of('a', 'b', 'c'), bytes => 5) ;

sub toggle_then_type
{
my ($rig, @names) = @_ ;

$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command("toggle $_")) for @names ;

type($rig, 'x') ;

return ;
}

#--#

type($engine, 'x') ;
toggle_then_type($engine, 'c') ;
toggle_then_type($engine, 'b') ;
toggle_then_type($engine, 'c') ;
toggle_then_type($engine, 'b', 'c') ;

is(received($engine), '32132', 'a running instance keeps the order of the chain when profiles are toggled') ;

done_testing ;
