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

profile_file('a', 'map x=a', 'block q') ;
profile_file('b', 'map x=b', 'map y=b') ;
profile_file('gaming', 'map x=g', 'block w') ;

# enabling a profile that is not loaded

my $chain = chain_of('a') ;

is_deeply([ $chain->profile_names ], ['a'], 'a chain starts with the profiles it was given') ;
is_deeply([ $chain->active_names ], ['a'], 'and they are active') ;
ok($chain->is_known('a') && $chain->is_active('a'), 'a is known and active') ;
ok(!$chain->is_known('gaming') && !$chain->is_active('gaming'), 'gaming is neither') ;

is($chain->enable('gaming'), 1, 'enable loads a profile and activates it') ;
is_deeply([ $chain->profile_names ], ['a', 'gaming'], 'it is added after the others') ;
is_deeply([ $chain->active_names ], ['a', 'gaming'], 'and is active') ;
is_deeply([ $chain->order ], ['a', 'gaming', 'keyfilter_command_line', 'keyfilter_runtime'], 'in the order of the chain') ;
ok($chain->is_known('gaming') && $chain->is_active('gaming'), 'it is known and active now') ;
is($chain->rules->process('x'), 'g', 'its rules apply, after those of the others') ;
is($chain->rules->process('w'), '', 'and add to them') ;
is($chain->rules->process('q'), '', 'while the others stay') ;

is($chain->enable('gaming'), 0, 'enabling an active profile changes nothing') ;
is_deeply([ $chain->active_names ], ['a', 'gaming'], 'it is not added twice') ;
is_deeply([ $chain->profile_names ], ['a', 'gaming'], 'neither is it loaded twice') ;
is($chain->enable('a'), 0, 'also for a profile that was there from the start') ;

is($chain->enable('b'), 1, 'another profile can be enabled') ;
is_deeply([ $chain->active_names ], ['a', 'gaming', 'b'], 'after the others, in the order they were enabled') ;
is($chain->rules->process('x'), 'b', 'the last one wins') ;
is($chain->rules->process('y'), 'b', 'and brings its own rules') ;

# the same profile by another name

my $by_path = chain_of('a') ;

is($by_path->enable("$profiles/b.profile"), 1, 'a profile can be given as a path') ;
is_deeply([ $by_path->profile_names ], ['a', 'b'], 'it is known by the name of its file') ;
is($by_path->enable('b'), 0, 'then it is the same profile as the name') ;
is($by_path->enable("$profiles/b.profile"), 0, 'and as the path') ;

write_file("$dir/local.profile", "map x=local\n") ;

is($by_path->enable("$dir/local.profile"), 1, 'a profile outside the profile directory can be enabled by its path') ;
is($by_path->rules->process('x'), 'local', 'and works') ;

# errors

my $before = [ $chain->active_names ] ;

like(failure_of(sub { $chain->enable('nope') ; }), qr/\Amissing profile 'nope', looked for '\Q$profiles\E\/nope\.profile'/, 'a profile that does not exist is a fatal error') ;
like(failure_of(sub { $chain->enable("$dir/missing.profile") ; }), qr/\Amissing profile '\Q$dir\E\/missing\.profile'/, 'also a path') ;
like(failure_of(sub { $chain->enable('') ; }), qr/\Ano profile name/, 'a name is needed') ;
like(failure_of(sub { $chain->enable(undef) ; }), qr/\Ano profile name/, 'and not undef') ;
like(failure_of(sub { $chain->enable('keyfilter_runtime') ; }), qr/\Areserved profile name 'keyfilter_runtime'/, 'the runtime profile cannot be enabled') ;
like(failure_of(sub { $chain->enable('keyfilter_command_line') ; }), qr/\Areserved profile name 'keyfilter_command_line'/, 'nor the command line profile') ;

profile_file('broken', 'block a', 'bogus') ;

like(failure_of(sub { $chain->enable('broken') ; }), qr/broken\.profile:2: unknown command 'bogus'/, 'a profile with an error names the file and the line') ;
is_deeply([ $chain->active_names ], $before, 'a profile that fails changes nothing') ;
is_deeply([ $chain->profile_names ], ['a', 'gaming', 'b'], 'and is not kept') ;

# includes and startup

profile_file('shared', 'map s=shared') ;
profile_file('with-include', 'include shared.profile', 'map i=inc', 'send-startup hello', 'startup-delay 5') ;

my $inc = chain_of('a') ;

$inc->enable('with-include') ;

is($inc->rules->process('s'), 'shared', 'an enabled profile has its includes') ;
is($inc->rules->process('i'), 'inc', 'and its own rules') ;
is_deeply([ $inc->startup->actions ], ['hello'], 'its startup commands are part of the startup of the chain') ;

# runtime rules and the command line stay after

my $layers = KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$profiles/a.profile") ], command_line => [ parsed('map x=cl') ]) ;

$layers->add_runtime($_) for parsed('map y=rt') ;
$layers->enable('b') ;

is($layers->rules->process('x'), 'cl', 'the command line still overrides an enabled profile') ;
is($layers->rules->process('y'), 'rt', 'and so does the runtime profile') ;
is_deeply([ $layers->order ], ['a', 'b', 'keyfilter_command_line', 'keyfilter_runtime'], 'they stay after all the profiles') ;

# in a running engine

my $counter = 0 ;
my @writers ;

sub rig
{
my (%options) = @_ ;

my $name = 'case' . ++$counter ;

my ($input, $writer) = pipe_pair() ;

push @writers, $writer ;

my $pty = start_engine({ input => $input, chain => $options{chain}, control => $options{control} }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/$name.ready ; head -c $options{bytes} > $dir/$name.out") ;

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

my $engine = rig(chain => chain_of('a'), bytes => 3) ;

type($engine, 'xw') ;

is($engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle gaming')), 1, 'a toggle command enables a profile in a running instance') ;
is_deeply([ $engine->{chain}->active_names ], ['a', 'gaming'], 'in the chain') ;
type($engine, 'xw') ;

is(received($engine), 'awg', 'what is typed after it is filtered by the new profile, what was typed before is not changed') ;

my $missing = rig(chain => chain_of('a'), bytes => 1) ;

is($missing->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle nope')), 0, 'a toggle of a profile that does not exist is not applied') ;
like(($missing->{pty}->command_errors)[0], qr/\Amissing profile 'nope'/, 'and the engine says why') ;

type($missing, 'x') ;

is(received($missing), 'a', 'the engine goes on with the profiles it had') ;

my $control = KeyFilter::Control->new(dir => "$dir/sockets") ;
my $served  = rig(chain => chain_of('a'), control => $control, bytes => 2) ;
my $client  = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($client, "toggle b\n") ;

my $deadline = Time::HiRes::time() + 5 ;

$served->{pty}->pump(0.05) until $served->{chain}->is_active('b') || Time::HiRes::time() > $deadline ;

ok($served->{chain}->is_active('b'), 'a toggle sent to the socket enables the profile') ;

type($served, 'xy') ;

is(received($served), 'bb', 'and its rules apply') ;

done_testing ;
