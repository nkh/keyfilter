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

profile_file('a', 'map x=a', 'block q') ;
profile_file('b', 'map x=b', 'map y=b', 'block r') ;
profile_file('c', 'map x=c') ;

# disabling

my $chain = chain_of('a', 'b', 'c') ;

is($chain->rules->process('x'), 'c', 'with the three profiles the last one wins') ;
is($chain->disable('c'), 1, 'disable turns an active profile off') ;
is_deeply([ $chain->active_names ], ['a', 'b'], 'it leaves the active profiles') ;
is_deeply([ $chain->profile_names ], ['a', 'b', 'c'], 'but stays known') ;
ok($chain->is_known('c') && !$chain->is_active('c'), 'known and not active') ;
is($chain->rules->process('x'), 'b', 'its rules no longer apply, those of the others do') ;
is_deeply([ $chain->order ], ['a', 'b', 'keyfilter_command_line', 'keyfilter_runtime'], 'the order shows the active profiles') ;
is($chain->disable('c'), 0, 'disabling it again changes nothing') ;
is($chain->disable('nobody'), 0, 'neither does disabling a profile that is not known') ;
is_deeply([ $chain->profile_names ], ['a', 'b', 'c'], 'and nothing is added') ;

is($chain->disable('b'), 1, 'another profile can be disabled') ;
is($chain->rules->process('x'), 'a', 'the rules of the first one are what is left') ;
is($chain->rules->process('y'), 'y', 'a rule of a disabled profile is gone') ;
is($chain->rules->process('r'), 'r', 'also a block') ;
is($chain->rules->process('q'), '', 'and the block of the active one stays') ;

is($chain->disable('a'), 1, 'all of them can be disabled') ;
is_deeply([ $chain->active_names ], [], 'none is active') ;
is($chain->rules->count, 0, 'there is no rule') ;
is_deeply([ $chain->order ], ['keyfilter_command_line', 'keyfilter_runtime'], 'only the command line and the runtime are left') ;

is($chain->enable('b'), 1, 'a disabled profile can be enabled again') ;
is($chain->rules->process('y'), 'b', 'with its rules') ;

is($chain->disable("$profiles/b.profile"), 1, 'a profile can be disabled by its path') ;

like(failure_of(sub { $chain->disable('keyfilter_runtime') ; }), qr/\Areserved profile name 'keyfilter_runtime'/, 'the runtime profile cannot be disabled') ;
like(failure_of(sub { $chain->disable('keyfilter_command_line') ; }), qr/\Areserved profile name 'keyfilter_command_line'/, 'nor the command line profile') ;
like(failure_of(sub { $chain->disable('') ; }), qr/\Ano profile name/, 'a name is needed') ;
like(failure_of(sub { $chain->disable(undef) ; }), qr/\Ano profile name/, 'and not undef') ;

# the other layers stay

my $layers = KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$profiles/a.profile"), KeyFilter::Profile::load("$profiles/b.profile") ], command_line => [ parsed('map z=cl') ]) ;

$layers->add_runtime($_) for parsed('map w=rt') ;
$layers->disable('a') ;
$layers->disable('b') ;

is($layers->rules->process('z'), 'cl', 'the command line stays when all profiles are disabled') ;
is($layers->rules->process('w'), 'rt', 'and so does the runtime profile') ;
is($layers->rules->count, 2, 'and they are all that is left') ;

# toggle

my $toggled = chain_of('a') ;

is($toggled->toggle('a'), 'disabled', 'toggle turns an active profile off') ;
is($toggled->rules->process('q'), 'q', 'and its rules are gone') ;
is($toggled->toggle('a'), 'enabled', 'turns it back on') ;
is($toggled->rules->process('q'), '', 'and its rules are back') ;
is($toggled->toggle('b'), 'enabled', 'a profile that was never loaded is loaded and turned on') ;
is_deeply([ sort $toggled->active_names ], ['a', 'b'], 'and is active') ;
is($toggled->toggle('b'), 'disabled', 'and turned off') ;
is($toggled->toggle("$profiles/b.profile"), 'enabled', 'by its path as by its name') ;

for my $round (1 .. 5)
	{
	$toggled->toggle('c') ;
	}

ok($toggled->is_active('c'), 'an odd number of toggles leaves a profile on') ;

$toggled->toggle('c') ;

ok(!$toggled->is_active('c'), 'an even number leaves it off') ;

like(failure_of(sub { $toggled->toggle('nope') ; }), qr/\Amissing profile 'nope'/, 'toggling a profile that does not exist is fatal') ;
like(failure_of(sub { $toggled->toggle('keyfilter_runtime') ; }), qr/\Areserved profile name/, 'toggling a reserved name too') ;
like(failure_of(sub { $toggled->toggle('') ; }), qr/\Ano profile name/, 'toggling nothing') ;
ok($toggled->is_active('a'), 'a toggle that fails changes nothing') ;

# what belongs to a profile

profile_file('shared', 'map s=shared') ;
profile_file('p1', 'include shared.profile', 'map i=one', 'send-startup one') ;
profile_file('p2', 'include shared.profile', 'map j=two', 'send-startup two') ;

my @loaded  = KeyFilter::Profile::load_profiles('p1', 'p2') ;
my $include = KeyFilter::Chain->new(profiles => \@loaded) ;

is($include->rules->process('s'), 'shared', 'an included file is part of the profile') ;
$include->disable('p1') ;

is($include->rules->process('i'), 'i', 'its own rules are gone') ;
is($include->rules->process('s'), 's', 'and the rules of the files it included, which belong to the profile that loaded them first') ;
is($include->rules->process('j'), 'two', 'the other profile is not affected') ;
is_deeply([ $include->startup->actions ], ['two'], 'the startup commands of a disabled profile are not those of the chain') ;

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

my $engine = rig(chain => chain_of('a', 'b'), bytes => 5) ;

type($engine, 'xq') ;

is($engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle b')), 1, 'a toggle command turns a profile off in a running instance') ;
ok(!$engine->{chain}->is_active('b'), 'in the chain') ;

type($engine, 'xy') ;

is($engine->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle b')), 1, 'and on again') ;
ok($engine->{chain}->is_active('b'), 'in the chain') ;

type($engine, 'xy') ;

is(received($engine), 'bayb' . 'b', 'what is typed is filtered by the profiles that are active at that time') ;

my $control = KeyFilter::Control->new(dir => "$dir/sockets") ;
my $served  = rig(chain => chain_of('a', 'b'), control => $control, bytes => 3) ;
my $client  = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($client, "toggle b\n") ;

my $deadline = Time::HiRes::time() + 5 ;

$served->{pty}->pump(0.05) until !$served->{chain}->is_active('b') || Time::HiRes::time() > $deadline ;

ok(!$served->{chain}->is_active('b'), 'a toggle sent to the socket turns a profile off') ;

type($served, 'xyr') ;

is(received($served), 'ayr', 'and its rules no longer apply') ;

done_testing ;
