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

profile_file('a', 'map x=1', 'block q') ;
profile_file('b', 'map x=2', 'map y=b') ;
profile_file('c', 'map x=3') ;

# the rules are built once and kept

my $chain = chain_of('a', 'b') ;

is($chain->generation, 0, 'a new chain is at generation 0') ;

my $rules = $chain->rules ;

isa_ok($rules, 'KeyFilter::Rules') ;
is($chain->rules, $rules, 'the rules are not built again when nothing changed') ;
is($chain->rules, $rules, 'as often as they are asked for') ;
is($chain->generation, 0, 'and the generation stays') ;
is($rules->count, 4, 'they are the rules of the active profiles') ;

# every change builds them again

$chain->add_runtime($_) for parsed('map z=runtime') ;

is($chain->generation, 1, 'a runtime command is a change') ;
isnt($chain->rules, $rules, 'the rules are new') ;
is($chain->rules->count, 5, 'with the new rule') ;
is($rules->count, 4, 'the old rules are not changed') ;

my $second = $chain->rules ;

is($chain->enable('c'), 1, 'enabling a profile is a change') ;
is($chain->generation, 2, 'it counts') ;
isnt($chain->rules, $second, 'the rules are new') ;
is($chain->rules->process('x'), '3', 'with the rules of the profile') ;

my $third = $chain->rules ;

is($chain->enable('c'), 0, 'enabling an active profile is not a change') ;
is($chain->generation, 2, 'it does not count') ;
is($chain->rules, $third, 'and the rules are kept') ;

is($chain->disable('c'), 1, 'disabling a profile is a change') ;
is($chain->generation, 3, 'it counts') ;
isnt($chain->rules, $third, 'the rules are new') ;
is($chain->rules->process('x'), '2', 'without the rules of the profile') ;

my $fourth = $chain->rules ;

is($chain->disable('c'), 0, 'disabling a profile that is off is not a change') ;
is($chain->disable('nobody'), 0, 'neither is disabling one that is not known') ;
is($chain->generation, 3, 'they do not count') ;
is($chain->rules, $fourth, 'and the rules are kept') ;

is($chain->toggle('c'), 'enabled', 'a toggle is a change') ;
is($chain->generation, 4, 'it counts') ;
is($chain->toggle('c'), 'disabled', 'in both directions') ;
is($chain->generation, 5, 'it counts again') ;

my $fifth = $chain->rules ;

failure_of(sub { $chain->enable('nope') ; }) ;
failure_of(sub { $chain->toggle('nope') ; }) ;
failure_of(sub { $chain->add_runtime(scalar KeyFilter::Command::parse_command('send x')) ; }) ;
failure_of(sub { $chain->disable('keyfilter_runtime') ; }) ;

is($chain->generation, 5, 'a change that fails is not a change') ;
is($chain->rules, $fifth, 'and the rules are kept') ;

# rebuilding

my $before  = $chain->generation ;
my $rebuilt = $chain->rebuild ;

isnt($rebuilt, $fifth, 'rebuild gives new rules') ;
is($chain->rules, $rebuilt, 'which are the rules of the chain') ;
is($chain->generation, $before + 1, 'it is a change') ;

sub describe_rules { return map { $_->{cmd} . ':' . ($_->{key} // join('', @{$_->{keys}})) . ($_->{replacement} // '') } $_[0]->rules ; }

# -----------------------------------------------------------------------------

is_deeply([ describe_rules($rebuilt) ], [ describe_rules($fifth) ], 'with the same rules') ;

# the order of the layers

my $layers = KeyFilter::Chain->new(profiles => [ map { KeyFilter::Profile::load("$profiles/$_.profile") } 'a', 'b', 'c' ], command_line => [ parsed('map x=cl', 'block w') ]) ;

$layers->add_runtime($_) for parsed('map x=rt', 'block v') ;
$layers->disable('b') ;
$layers->disable('a') ;
$layers->enable('b') ;

is_deeply([ describe_rules($layers->rules) ], ['map:x2', 'map:yb', 'map:x3', 'map:xcl', 'block:w', 'map:xrt', 'block:v'], 'the rules are those of the active profiles in the order of the chain, then the command line, then the runtime profile') ;

# whatever happens the rules are those of the state

srand(7) ;

my @names   = ('a', 'b', 'c') ;
my %active  = map { $_ => 1 } 'a', 'b' ;
my $random  = chain_of('a', 'b') ;
my %winner  = (a => 1, b => 2, c => 3) ;
my %size    = (a => 2, b => 2, c => 1) ;
my $wrong   = 0 ;
my $runtime = 0 ;

for my $round (1 .. 300)
	{
	my $name = $names[int rand @names] ;
	my $do   = int rand 4 ;
	
	if ($do == 0)
		{
		$random->enable($name) ;
		
		$active{$name} = 1 ;
		}
	elsif ($do == 1)
		{
		$random->disable($name) ;
		
		delete $active{$name} ;
		}
	elsif ($do == 2)
		{
		$random->toggle($name) ;
		
		$active{$name} ? delete $active{$name} : ($active{$name} = 1) ;
		}
	else
		{
		$random->add_runtime($_) for parsed("map 1=$round") ;
		
		$runtime++ ;
		}
	
	my @expected = grep { $active{$_} } @names ;
	my ($last)   = reverse @expected ;
	my $count    = $runtime ;
	
	$count += $size{$_} for @expected ;
	
	$wrong++ unless $random->rules->count == $count && $random->rules->process('x') eq (defined $last ? $winner{$last} : 'x') ;
	}

is($wrong, 0, 'after three hundred random changes the rules are always those of the state') ;

# it is quick

write_file("$profiles/big.profile", map { 'map ' . chr(97 + $_ % 26) . '=' . $_ . "\n" } 1 .. 3000) ;

my $big = KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$profiles/big.profile") ]) ;

$big->rules ;

my $began = Time::HiRes::time() ;

$big->rules for 1 .. 20000 ;

cmp_ok(Time::HiRes::time() - $began, '<', 0.5, 'asking for the rules of three thousand rules twenty thousand times is quick') ;

# finding the rules of a key does not depend on how many there are

my $store = KeyFilter::Rules->new() ;

$store->add($_) for parsed('block a a', 'map b=x') ;

is(scalar(() = $store->matching_rules('a')), 1, 'a rule that names a key twice matches once') ;
is($store->process('a'), '', 'and blocks it') ;

$store->add($_) for parsed('unblock a') ;

is($store->process('a'), 'a', 'a rule that is added is found') ;
is_deeply([ map { $_->{cmd} } $store->matching_rules('a') ], ['block', 'unblock'], 'in declaration order') ;

$store->clear ;

is($store->process('a'), 'a', 'and rules that are cleared are not') ;
is(scalar(() = $store->matching_rules('b')), 0, 'none is left') ;

my $thousands = KeyFilter::Rules->new() ;

$thousands->add($_) for parsed(map { 'map ' . chr(97 + $_ % 26) . "=$_" } 1 .. 5000) ;

$began = Time::HiRes::time() ;

$thousands->process('a') for 1 .. 20000 ;

cmp_ok(Time::HiRes::time() - $began, '<', 1, 'twenty thousand keys through five thousand rules take a moment') ;

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

my $pending = $bytes ;
my $deadline = Time::HiRes::time() + 60 ;

$rig->{writer}->blocking(0) ;

while (Time::HiRes::time() < $deadline)
	{
	if (length $pending)
		{
		my $written = syswrite($rig->{writer}, $pending) ;
		
		substr($pending, 0, $written, '') if defined $written ;
		}
	
	return 1 if !length $pending && !IO::Select->new($rig->{input})->can_read(0) && !$rig->{pty}->pending_input && !defined $rig->{pty}->key_remaining ;
	
	$rig->{pty}->pump(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

sub received { my ($rig) = @_ ; $rig->{pty}->wait_exit ; return read_file($rig->{out}) ; }

# -----------------------------------------------------------------------------

my $engine = rig(chain => chain_of('a', 'b'), bytes => 4) ;

is($engine->{pty}->rules, $engine->{chain}->rules, 'the engine uses the rules of its chain') ;

type($engine, 'x') ;
$engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command($_)) for 'toggle c', 'map x=m' ;
type($engine, 'x') ;
$engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle c')) ;
type($engine, 'x') ;
$engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle b')) ;
type($engine, 'x') ;

is(received($engine), '2mmm', 'what is typed is always filtered by the rules of the moment') ;

my $many = rig(chain => $big, bytes => 80000) ;

$began = Time::HiRes::time() ;

type($many, 'a' x 20000) ;

cmp_ok(Time::HiRes::time() - $began, '<', 20, 'twenty thousand keys are filtered by three thousand rules in a moment') ;
ok(received($many) eq '2990' x 20000, 'and come out as the last rule for the key says') ;

done_testing ;
