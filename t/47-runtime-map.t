#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use IO::Select () ;
use IO::Socket::UNIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir     = temp_dir() ;
my $counter = 0 ;
my @writers ;

sub parsed { return map { scalar KeyFilter::Command::parse_command($_) } @_ ; }

# -----------------------------------------------------------------------------

sub chain_of
{
my (@lines) = @_ ;

my $name = 'p' . ++$counter ;

write_file("$dir/$name.profile", map { "$_\n" } @lines) ;

return KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$dir/$name.profile") ]) ;
}

# -----------------------------------------------------------------------------

sub rig
{
my (%options) = @_ ;

my $name = 'case' . ++$counter ;

my ($input, $writer) = pipe_pair() ;

push @writers, $writer ;

my $chain = $options{chain} // KeyFilter::Chain->new() ;
my $pty   = start_engine({ input => $input, chain => $chain, key_timeout => $options{key_timeout}, control => $options{control}, recorder => $options{recorder} }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/$name.ready ; head -c $options{bytes} > $dir/$name.out") ;

die "the child is not ready\n" unless wait_for_file("$dir/$name.ready") ;

return { pty => $pty, writer => $writer, input => $input, chain => $chain, out => "$dir/$name.out" } ;
}

# -----------------------------------------------------------------------------

sub settle
{
my ($rig) = @_ ;

my $deadline = Time::HiRes::time() + 20 ;

while (Time::HiRes::time() < $deadline)
	{
	my $waiting = IO::Select->new($rig->{input})->can_read(0) ;
	
	return 1 if !$waiting && !$rig->{pty}->pending_input && !defined $rig->{pty}->key_remaining ;
	
	$rig->{pty}->pump(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

sub type
{
my ($rig, $bytes) = @_ ;

syswrite($rig->{writer}, $bytes) ;

return settle($rig) ;
}

# -----------------------------------------------------------------------------

sub received
{
my ($rig) = @_ ;

$rig->{pty}->wait_exit ;

return read_file($rig->{out}) ;
}

# -----------------------------------------------------------------------------

sub pump_until
{
my ($rig, $condition) = @_ ;

my $deadline = Time::HiRes::time() + 5 ;

$rig->{pty}->pump(0.05) until $condition->() || Time::HiRes::time() > $deadline ;

return $condition->() ;
}

# -----------------------------------------------------------------------------

sub runtime_count { return scalar(() = $_[0]->runtime_commands) ; }

# -----------------------------------------------------------------------------

# a runtime map

my $rig = rig(bytes => 6) ;

type($rig, 'xay') ;
$rig->{chain}->add_runtime($_) for parsed('map a=b') ;
type($rig, 'xay') ;

is(received($rig), 'xayxby', 'a runtime map applies to the keys typed after it') ;

$rig = rig(bytes => 11) ;

$rig->{chain}->add_runtime($_) for parsed('map F1=git status<<Enter>>') ;
type($rig, "\eOP") ;

is(received($rig), "git status\r", 'a key can be replaced by text and key symbols') ;

$rig = rig(bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('map z=<<Up>>') ;
type($rig, 'z') ;

is(received($rig), "\e[A", 'a key can be replaced by a sequence') ;

$rig = rig(bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('map a=x\ty') ;
type($rig, 'a') ;

is(received($rig), "x\ty", 'escapes are resolved in the replacement') ;

$rig = rig(bytes => 2) ;

$rig->{chain}->add_runtime($_) for parsed('map a=') ;
type($rig, 'bac') ;

is(received($rig), 'bc', 'an empty replacement removes the key') ;

$rig = rig(bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('map a=1', 'map a=2') ;
type($rig, 'a') ;

$rig->{chain}->add_runtime($_) for parsed('map a=3') ;
type($rig, 'aa') ;

is(received($rig), '233', 'the last map of a key wins') ;

$rig = rig(bytes => 2) ;

$rig->{chain}->add_runtime($_) for parsed('map a=b', 'map b=c') ;
type($rig, 'ab') ;

is(received($rig), 'bc', 'maps do not chain, each key is mapped on its own') ;

$rig = rig(chain => chain_of('map a=p', 'map c=q'), bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('map a=r') ;
type($rig, 'acb') ;

is(received($rig), 'rqb', 'a runtime map overrides a map of a profile, the others stay') ;

$rig = rig(bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('map a=b', 'block a') ;
type($rig, 'a') ;
$rig->{chain}->add_runtime($_) for parsed('unblock a') ;
type($rig, 'a') ;
type($rig, 'cd') ;

is(received($rig), 'bcd', 'a mapped key that is blocked gives nothing, until it is unblocked') ;

$rig = rig(bytes => 2) ;

$rig->{chain}->add_runtime($_) for parsed('map a=b', 'block b') ;
type($rig, 'abc') ;

is(received($rig), 'bc', 'what a map gives is not blocked, only what is typed is') ;

# keys that are sequences

$rig = rig(bytes => 4) ;

$rig->{chain}->add_runtime($_) for parsed('map Up=u', 'map M-b=v', 'map C-a=w', 'map F5=x') ;
type($rig, "\e[A\eb\x01\e[15~") ;

is(received($rig), 'uvwx', 'keys that are sequences are mapped') ;

$rig = rig(bytes => 2) ;

$rig->{chain}->add_runtime($_) for parsed('map Up=u') ;

syswrite($rig->{writer}, "\e[") ;

$rig->{pty}->pump(0.1) ;

syswrite($rig->{writer}, 'A') ;

settle($rig) ;

syswrite($rig->{writer}, 'k') ;

settle($rig) ;

is(received($rig), 'uk', 'a sequence that arrives in pieces is mapped as a whole') ;

$rig = rig(bytes => 1) ;

$rig->{chain}->add_runtime($_) for parsed('map Esc=q') ;
type($rig, "\e") ;

is(received($rig), 'q', 'a lone escape is mapped after the timeout') ;

# what the child gets

my $recorded = KeyFilter::Recorder->new(file => "$dir/mapped.rec") ;

$rig = rig(recorder => $recorded, bytes => 6) ;

$rig->{chain}->add_runtime($_) for parsed('map a=xyz') ;
type($rig, 'aa') ;
received($rig) ;
$recorded->close ;

is(join('', map { $_->{data} } grep { $_->{type} eq 'I' } KeyFilter::Recorder::parse_recording(read_file("$dir/mapped.rec"))), 'xyzxyz', 'the recording has what the child received, not what was typed') ;

my $text = 'x' x 10000 ;

$rig = rig(bytes => 10000) ;

$rig->{chain}->add_runtime($_) for parsed("map a=$text") ;
type($rig, 'a') ;

is(received($rig), $text, 'a long replacement is delivered completely') ;

my $many = rig(bytes => 3) ;

$many->{chain}->add_runtime($_) for parsed(map { 'map a=' . $_ } 1 .. 300) ;
type($many, 'a') ;

is(received($many), '300', 'a lot of runtime commands are fine, the last one wins') ;

# only for the running instance

my $one   = rig(bytes => 1) ;
my $other = rig(bytes => 1) ;

$one->{chain}->add_runtime($_) for parsed('map a=1') ;
type($one, 'a') ;
type($other, 'a') ;

is(received($one), '1', 'a runtime map works in its instance') ;
is(received($other), 'a', 'and not in another') ;

# startup text is not mapped

my ($startup_input, $startup_writer) = pipe_pair() ;
my $startup_chain = KeyFilter::Chain->new() ;

$startup_chain->add_runtime($_) for parsed('map a=b') ;

my $startup = KeyFilter::Startup->new(scalar KeyFilter::Command::parse_command('send-startup a')) ;
my $with_startup = start_engine({ input => $startup_input, chain => $startup_chain, startup => $startup }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/startup.ready ; head -c 1 > $dir/startup.out") ;

wait_for_file("$dir/startup.ready") ;

$with_startup->pump(0.05) for 1 .. 4 ;
$with_startup->wait_exit ;

is(read_file("$dir/startup.out"), 'a', 'the text of a startup is not mapped') ;

# commands

my $commanded = rig(bytes => 1) ;

is($commanded->{pty}->apply_command(scalar KeyFilter::Command::parse_command('map a=b')), 1, 'a map command is applied') ;
is(runtime_count($commanded->{chain}), 1, 'to the chain') ;
is($commanded->{chain}->rules->process('a'), 'b', 'which maps the key') ;
is(scalar(() = $commanded->{pty}->command_errors), 0, 'without an error') ;

$commanded->{pty}->signal('KILL') ;

# from the socket

my $control = KeyFilter::Control->new(dir => "$dir/sockets") ;

$rig = rig(control => $control, bytes => 5) ;

my $client = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($client, "map F1=hello\n") ;

pump_until($rig, sub { runtime_count($rig->{chain}) == 1 ; }) ;

type($rig, "\eOP") ;

is(received($rig), 'hello', 'a map sent to the socket applies') ;

my $live_control = KeyFilter::Control->new(dir => "$dir/sockets2") ;
my $engine       = engine_process({ chain => chain_of(), control => $live_control }, 'sh', '-c', 'stty raw -echo ; echo ready ; cat') ;

$engine->read_until(qr/ready\n/) ;

my $socket = IO::Socket::UNIX->new(Peer => $live_control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($socket, "map a=bc\nmap F2=<<Enter>>\n") ;

Time::HiRes::sleep(0.4) ;

$engine->send("a\eOQx") ;

is($engine->read_until(qr/x/), "bc\rx", 'in a process of its own, keys are mapped as they are typed') ;

$engine->signal('TERM') ;
$engine->finish ;

done_testing ;
