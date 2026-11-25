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

# a runtime send

my $rig = rig(bytes => 3) ;

is($rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send abc')), 1, 'a send command is applied') ;

settle($rig) ;

is(received($rig), 'abc', 'its text reaches the child') ;

$rig = rig(bytes => 11) ;

$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send git status<<Enter>>')) ;
settle($rig) ;

is(received($rig), "git status\r", 'key symbols are resolved in the text') ;

$rig = rig(bytes => 4) ;

$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send \x00\xff\n\t')) ;
settle($rig) ;

is(received($rig), "\x00\xff\n\t", 'any byte can be sent') ;

$rig = rig(bytes => 6) ;

$rig->{pty}->apply_command($_) for parsed('send one', 'send two') ;
settle($rig) ;

is(received($rig), 'onetwo', 'several sends arrive in order') ;

# no rules, no filter

$rig = rig(chain => chain_of('map a=b', 'block c'), bytes => 5) ;

$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send ac<<Up>>')) ;
settle($rig) ;

is(received($rig), "ac\e[A", 'the text of a send is not mapped or blocked') ;

my @seen ;
my ($filter_input, $filter_writer) = pipe_pair() ;
my $filtered = start_engine({ input => $filter_input, filter => sub { push @seen, $_[0] ; return '' ; } }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/filtered.ready ; head -c 3 > $dir/filtered.out") ;

wait_for_file("$dir/filtered.ready") ;

$filtered->apply_command(scalar KeyFilter::Command::parse_command('send abc')) ;
$filtered->pump(0.05) for 1 .. 3 ;
$filtered->wait_exit ;

is(read_file("$dir/filtered.out"), 'abc', 'nor is it given to the input filter') ;
is_deeply(\@seen, [], 'which never sees it') ;

# with the typing of the user

$rig = rig(bytes => 7) ;

type($rig, 'ab') ;
$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send XYZ')) ;
type($rig, 'cd') ;

is(received($rig), 'abXYZcd', 'a send comes after what was typed before it, and before what is typed after') ;

$rig = rig(chain => chain_of('block F9'), bytes => 2) ;

syswrite($rig->{writer}, "\e") ;

$rig->{pty}->pump(0.02) ;
$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send x')) ;

settle($rig) ;

is(received($rig), "x\e", 'a send does not wait for a key that is not finished') ;

# without a chain

my ($plain_input, $plain_writer) = pipe_pair() ;
my $plain = start_engine({ input => $plain_input }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/plain.ready ; head -c 5 > $dir/plain.out") ;

wait_for_file("$dir/plain.ready") ;

is($plain->apply_command(scalar KeyFilter::Command::parse_command('send hello')), 1, 'send needs no chain') ;
is($plain->apply_command(scalar KeyFilter::Command::parse_command('block a')), 0, 'a block does') ;

$plain->pump(0.05) for 1 .. 3 ;
$plain->wait_exit ;

is(read_file("$dir/plain.out"), 'hello', 'and is delivered') ;
like(($plain->command_errors)[0], qr/\Athe command 'block' needs a chain of profiles/, 'the block says what it needs') ;

# what is recorded

my $recorded = KeyFilter::Recorder->new(file => "$dir/sent.rec") ;

$rig = rig(recorder => $recorded, bytes => 5) ;

type($rig, 'ab') ;
$rig->{pty}->apply_command(scalar KeyFilter::Command::parse_command('send xyz')) ;
settle($rig) ;
received($rig) ;
$recorded->close ;

is(join('', map { $_->{data} } grep { $_->{type} eq 'I' } KeyFilter::Recorder::parse_recording(read_file("$dir/sent.rec"))), 'abxyz', 'what is sent is recorded as input, in order') ;

# a child that is gone, a long text

my ($gone_input, $gone_writer) = pipe_pair() ;
my $gone = start_engine({ input => $gone_input }, 'true') ;

$gone->wait_exit ;

is($gone->apply_command(scalar KeyFilter::Command::parse_command('send abc')), 1, 'a send to a child that is gone is applied') ;
is($gone->pending_input, 0, 'and dropped, without an error') ;

my $text = join('', map { chr(65 + $_ % 26) } 0 .. 99999) ;

$rig = rig(bytes => 100000) ;

$rig->{pty}->apply_command({ cmd => 'send', text => $text }) ;

pump_until($rig, sub { !$rig->{pty}->pending_input ; }) ;

is(received($rig), $text, 'a long text is delivered completely and in order') ;

# from the socket

my $control = KeyFilter::Control->new(dir => "$dir/sockets") ;

$rig = rig(control => $control, bytes => 15) ;

my $client = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;
my $other  = IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($client, "send one\n") ;

$rig->{pty}->pump(0.2) ;

syswrite($other, "send two\nsend three\n") ;
syswrite($client, "send four\n") ;

$rig->{pty}->pump(0.3) ;

my $got = received($rig) ;

is(length $got, 15, 'sends from the socket arrive') ;
like($got, qr/one.*four/, 'the lines of a client are in the order they were sent') ;
like($got, qr/two.*three/, 'also for the other client') ;
like($got, qr/\A(?:one|two)/, 'and nothing is lost') ;

# in a process of its own

my $live_control = KeyFilter::Control->new(dir => "$dir/sockets2") ;
my $engine       = engine_process({ control => $live_control }, 'sh', '-c', 'stty raw -echo ; echo ready ; cat') ;

$engine->read_until(qr/ready\n/) ;

my $socket = IO::Socket::UNIX->new(Peer => $live_control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($socket, "send hello<<Enter>>\n") ;

is($engine->read_until(qr/\r/), "hello\r", 'a send to the socket of a running instance reaches the child') ;

$engine->signal('TERM') ;
$engine->finish ;

my $shell_control = KeyFilter::Control->new(dir => "$dir/sockets3") ;
my $shell         = engine_process({ control => $shell_control }, 'sh', '-c', 'read x ; echo got:$x') ;

my $shell_socket = IO::Socket::UNIX->new(Peer => $shell_control->path, Type => Socket::SOCK_STREAM()) ;

syswrite($shell_socket, "send typed text\\n\n") ;

like($shell->read_all, qr/got:typed text\r\n/, 'a line sent to a shell is read by it') ;
is($shell->finish, 0, 'and the shell ends') ;

done_testing ;
