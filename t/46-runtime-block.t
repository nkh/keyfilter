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

# blocking keys

my $rig = rig(bytes => 5) ;

type($rig, 'hello') ;

is(received($rig), 'hello', 'without rules what is typed reaches the child') ;

$rig = rig(chain => chain_of('block x'), bytes => 4) ;

type($rig, 'axbxxcxd') ;

is(received($rig), 'abcd', 'the keys a profile blocks do not reach the child') ;

$rig = rig(bytes => 5) ;

type($rig, 'abc') ;
$rig->{chain}->add_runtime($_) for parsed('block b') ;
type($rig, 'abc') ;

is(received($rig), 'abcac', 'a runtime block applies to what is typed after it') ;

$rig = rig(chain => chain_of('block x'), bytes => 3) ;

type($rig, 'xa') ;
$rig->{chain}->add_runtime($_) for parsed('unblock x') ;
type($rig, 'xa') ;

is(received($rig), 'axa', 'a runtime unblock lets a blocked key through') ;

$rig = rig(bytes => 6) ;

type($rig, 'x') ;
$rig->{chain}->add_runtime($_) for parsed('block x') ;
type($rig, 'x') ;
$rig->{chain}->add_runtime($_) for parsed('unblock x') ;
type($rig, 'xyyyy') ;

is(received($rig), 'xxyyyy', 'a key can be blocked and unblocked again') ;

$rig = rig(bytes => 3) ;

$rig->{chain}->add_runtime($_) for parsed('block a b c') ;
type($rig, 'abcde') ;
$rig->{chain}->add_runtime($_) for parsed('unblock b') ;
type($rig, 'b') ;

is(received($rig), 'deb', 'several keys are blocked and one is unblocked') ;

# sequences

$rig = rig(chain => chain_of('block Up'), bytes => 6) ;

type($rig, "a\e[Ab\e[Bc") ;

is(received($rig), "ab\e[Bc", 'a key that is a sequence is blocked as a whole, the others are not') ;

$rig = rig(chain => chain_of('block Up'), bytes => 1) ;

syswrite($rig->{writer}, "\e[") ;

$rig->{pty}->pump(0.1) ;

syswrite($rig->{writer}, 'A') ;

settle($rig) ;

syswrite($rig->{writer}, 'z') ;

settle($rig) ;

is(received($rig), 'z', 'a sequence that arrives in pieces is blocked as a whole') ;

$rig = rig(chain => chain_of('block C-z', 'block M-a', 'block F5', 'block C-Up'), bytes => 4) ;

type($rig, "\x1a\ea\e[15~\e[1;5Aabcd") ;

is(received($rig), 'abcd', 'control keys, alt keys, function keys and combinations are blocked') ;

$rig = rig(chain => chain_of('block M-a'), bytes => 2) ;

type($rig, "a\eab") ;

is(received($rig), 'ab', 'a is not M-a') ;

$rig = rig(chain => chain_of('block 1b5b41'), bytes => 1) ;

type($rig, "\e[Az") ;

is(received($rig), 'z', 'a raw sequence is blocked') ;

$rig = rig(chain => chain_of('block Up'), bytes => 3) ;

type($rig, "abc\e[A") ;

is(received($rig), 'abc', 'keys in one chunk are all looked at') ;

# a lone escape

$rig = rig(chain => chain_of('block F9'), bytes => 2) ;

type($rig, "\e") ;
type($rig, 'a') ;

is(received($rig), "\ea", 'a lone escape is a key after the timeout, what follows is another key') ;

$rig = rig(chain => chain_of('block Esc'), bytes => 1) ;

type($rig, "\e") ;
type($rig, 'a') ;

is(received($rig), 'a', 'a lone escape can be blocked') ;

$rig = rig(chain => chain_of('block F9'), key_timeout => 0.4, bytes => 3) ;

syswrite($rig->{writer}, "\e") ;

$rig->{pty}->pump(0.15) ;

ok($rig->{pty}->key_remaining > 0.1, 'an escape waits for the rest of a sequence') ;
is($rig->{pty}->pending_input, 0, 'it is not sent yet') ;

syswrite($rig->{writer}, '[A') ;

settle($rig) ;

is(received($rig), "\e[A", 'with the rest it is one key') ;

$rig = rig(chain => chain_of('block F9'), key_timeout => 0.3, bytes => 1) ;

syswrite($rig->{writer}, "\e") ;

my $began = Time::HiRes::time() ;

settle($rig) ;

cmp_ok(Time::HiRes::time() - $began, '>=', 0.25, 'a lone escape is sent when the timeout is over') ;
cmp_ok(Time::HiRes::time() - $began, '<', 2, 'and not much later') ;
is(received($rig), "\e", 'it is the escape key') ;

is(KeyFilter::PTY->new(command => ['true'], chain => KeyFilter::Chain->new())->{key_timeout}, 0.05, 'the timeout is short by default') ;

# the end of the input

$rig = rig(chain => chain_of('block F9'), bytes => 3) ;

syswrite($rig->{writer}, "a\e") ;

close $rig->{writer} ;

pump_until($rig, sub { $rig->{pty}->input_eof && !$rig->{pty}->pending_input && !defined $rig->{pty}->key_remaining ; }) ;

is(received($rig), "a\e\x04", 'an unfinished key is sent before the end of the input') ;

# what is recorded

my $recorded = KeyFilter::Recorder->new(file => "$dir/blocked.rec") ;

$rig = rig(chain => chain_of('block x'), recorder => $recorded, bytes => 3) ;

type($rig, 'axbxc') ;
received($rig) ;
$recorded->close ;

is(join('', map { $_->{data} } grep { $_->{type} eq 'I' } KeyFilter::Recorder::parse_recording(read_file("$dir/blocked.rec"))), 'abc', 'what was blocked is not recorded') ;

# commands

my $commanded = rig(bytes => 2) ;

is($commanded->{pty}->apply_command(scalar KeyFilter::Command::parse_command('block x')), 1, 'a block command is applied') ;
is(runtime_count($commanded->{chain}), 1, 'to the chain') ;
is($commanded->{pty}->apply_command(scalar KeyFilter::Command::parse_command('unblock x')), 1, 'so is an unblock command') ;
is(runtime_count($commanded->{chain}), 2, 'and it is kept after it') ;

is($commanded->{pty}->apply_command(scalar KeyFilter::Command::parse_command('toggle x')), 0, 'a toggle of a profile that does not exist is not applied') ;
is($commanded->{pty}->apply_command(undef), 0, 'nothing is not a command') ;
is($commanded->{pty}->apply_command({ cmd => 'frobnicate' }), 0, 'an unknown command is not applied') ;

my @errors = $commanded->{pty}->command_errors ;

is(scalar @errors, 3, 'each of them is an error') ;
like($errors[0], qr/\Amissing profile 'x'/, 'which says what is wrong') ;

$commanded->{pty}->signal('KILL') ;

my $no_chain = KeyFilter::PTY->new(command => ['true']) ;

is($no_chain->apply_command(scalar KeyFilter::Command::parse_command('block x')), 0, 'without a chain a command is not applied') ;
like(($no_chain->command_errors)[0], qr/needs a chain of profiles/, 'and says why') ;

# commands from the socket

my $control = KeyFilter::Control->new(dir => "$dir/sockets") ;

$rig = rig(chain => chain_of('block q'), control => $control, bytes => 4) ;

my $client = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($client, "block x\n") ;

pump_until($rig, sub { runtime_count($rig->{chain}) == 1 ; }) ;

is(runtime_count($rig->{chain}), 1, 'a command sent to the socket reaches the chain') ;

type($rig, 'axqb') ;

syswrite($client, "unblock x\n") ;

pump_until($rig, sub { runtime_count($rig->{chain}) == 2 ; }) ;

type($rig, 'xc') ;

is(received($rig), 'abxc', 'it blocks and unblocks the keys that follow') ;

my $second_control = KeyFilter::Control->new(dir => "$dir/sockets2") ;
my $mixed          = rig(control => $second_control, bytes => 1) ;
my $mixed_client   = IO::Socket::UNIX->new(Peer => $second_control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($mixed_client, "bogus\nblock a\nstartup-delay 5\ntoggle no-such-profile-xyz\nblock b\n") ;

pump_until($mixed, sub { runtime_count($mixed->{chain}) >= 2 && scalar(() = $mixed->{pty}->command_errors) >= 1 ; }) ;

is_deeply([ map { $_->{keys}[0] } $mixed->{chain}->runtime_commands ], ['a', 'b'], 'the right commands among wrong ones are applied') ;
is(scalar(() = $second_control->errors), 2, 'the control keeps its errors, a bad line and a refused command') ;
is(scalar(() = $mixed->{pty}->command_errors), 1, 'the engine keeps the command it cannot apply yet') ;

type($mixed, 'z') ;

is(received($mixed), 'z', 'the engine goes on') ;

# the whole thing, in a process of its own

my $live_control = KeyFilter::Control->new(dir => "$dir/sockets3") ;
my $engine       = engine_process({ chain => chain_of(), control => $live_control }, 'sh', '-c', 'stty raw -echo ; echo ready ; cat') ;

$engine->read_until(qr/ready\n/) ;
$engine->send('a') ;

is($engine->read_until(qr/a/), 'a', 'what is typed goes to the child') ;

my $socket = IO::Socket::UNIX->new(Peer => $live_control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($socket, "block x\n") ;

Time::HiRes::sleep(0.4) ;

$engine->send('xy') ;

is($engine->read_until(qr/y/), 'y', 'after a runtime block the key is blocked') ;

syswrite($socket, "unblock x\n") ;

Time::HiRes::sleep(0.4) ;

$engine->send('xz') ;

is($engine->read_until(qr/z/), 'xz', 'and after an unblock it is not') ;

$engine->signal('TERM') ;
$engine->finish ;

ok(!-e $live_control->path, 'the socket is removed when the instance ends') ;

done_testing ;
