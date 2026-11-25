#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub startup_from { return KeyFilter::Startup->new(map { scalar KeyFilter::Command::parse_command($_) } @_) ; }

# -----------------------------------------------------------------------------

my $dir     = temp_dir() ;
my $counter = 0 ;
my @writers ;

# a child that puts its terminal in raw mode, says it is ready and collects what it receives

sub collector
{
my (%options) = @_ ;

my $name = 'case' . ++$counter ;

my ($input, $writer) = pipe_pair() ;

push @writers, $writer ;

my $pty = start_engine({ input => $input, startup => $options{startup}, filter => $options{filter} }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/$name.ready ; head -c $options{bytes} > $dir/$name.out") ;

die "the child is not ready\n" unless wait_for_file("$dir/$name.ready") ;

return { pty => $pty, writer => $writer, out => "$dir/$name.out" } ;
}

# -----------------------------------------------------------------------------

sub pump_until
{
my ($pty, $condition, $timeout) = @_ ;

my $deadline = Time::HiRes::time() + ($timeout // 20) ;

while (Time::HiRes::time() < $deadline)
	{
	return 1 if $condition->() ;
	
	$pty->pump(0.02) ;
	}

return $condition->() ? 1 : 0 ;
}

# -----------------------------------------------------------------------------

sub delivered
{
my ($case) = @_ ;

pump_until($case->{pty}, sub { $case->{pty}->startup_fired && !$case->{pty}->pending_input ; }) ;

$case->{pty}->wait_exit ;

return read_file($case->{out}) ;
}

# -----------------------------------------------------------------------------

# the actions of a startup

is_deeply([ KeyFilter::Startup->new()->actions ], [], 'without commands there is no action') ;
is_deeply([ startup_from('startup-delay 100')->actions ], [], 'a delay is not an action') ;
is_deeply([ startup_from('send-startup abc')->actions ], ['abc'], 'send-startup is an action') ;
is_deeply([ startup_from('send-startup a', 'send-startup b', 'send-startup c')->actions ], ['a', 'b', 'c'], 'actions keep their order') ;
is_deeply([ startup_from('send-startup source env.sh\n')->actions ], ["source env.sh\n"], 'escapes are resolved') ;
is_deeply([ startup_from('send-startup ls<<Enter>>')->actions ], ["ls\r"], 'key symbols are resolved') ;
is_deeply([ startup_from('send-startup <<Up>><<C-a>>')->actions ], ["\e[A\x01"], 'several key symbols') ;
is_deeply([ startup_from('send-startup \x00\xff')->actions ], ["\x00\xff"], 'any byte can be sent') ;
is_deeply([ startup_from('send-startup a', 'startup-delay 5', 'send-startup b')->actions ], ['a', 'b'], 'a delay between actions is not an action') ;
is_deeply([ startup_from('send-startup \x20x')->actions ], [' x'], 'an action can start with a space') ;
is_deeply([ startup_from('send-startup x ')->actions ], ['x '], 'or end with one') ;

is(KeyFilter::Startup->new()->text, '', 'the text of nothing is empty') ;
is(startup_from('send-startup a', 'send-startup b<<Enter>>', 'send-startup c')->text, "ab\rc", 'the text is all the actions, one after the other') ;

my $startup = startup_from('send-startup a', 'send-startup b') ;
my @copy    = $startup->actions ;

push @copy, 'changed' ;
$copy[0] = 'changed' ;

is_deeply([ $startup->actions ], ['a', 'b'], 'the actions of a startup cannot be changed from outside') ;

# the actions reach the child

my $case = collector(bytes => 3, startup => startup_from('send-startup abc')) ;

is(delivered($case), 'abc', 'the text of a startup reaches the child') ;

$case = collector(bytes => 9, startup => startup_from('send-startup abc', 'send-startup def', 'send-startup ghi')) ;

is(delivered($case), 'abcdefghi', 'several actions arrive in order') ;

$case = collector(bytes => 13, startup => startup_from('send-startup git status<<Enter>>', 'send-startup \x00\xff')) ;

is(delivered($case), "git status\r\x00\xff", 'key symbols and any byte arrive as they are') ;

$case = collector(bytes => 9, startup => startup_from('send-startup <<Up>><<C-a>>', 'send-startup <<F5>>')) ;

is(delivered($case), "\e[A\x01\e[15~", 'sequences arrive as the terminal would send them') ;

# nothing before the delay

$case = collector(bytes => 3, startup => startup_from('startup-delay 600', 'send-startup abc')) ;

my $spawned = Time::HiRes::time() ;

$case->{pty}->pump(0.1) ;
$case->{pty}->pump(0.1) ;

is($case->{pty}->pending_input, 0, 'nothing is pending before the delay') ;
is($case->{pty}->is_running, 1, 'and the child is still waiting') ;
is($case->{pty}->startup_fired, 0, 'the startup has not fired') ;

is(delivered($case), 'abc', 'the text arrives after the delay') ;

# not through the filter, not twice

my @filtered ;

$case = collector(bytes => 3, startup => startup_from('send-startup abc'), filter => sub { push @filtered, $_[0] ; return '' ; }) ;

is(delivered($case), 'abc', 'the text of a startup is not touched by the input filter') ;
is_deeply(\@filtered, [], 'which never sees it') ;

$case = collector(bytes => 5, startup => startup_from('send-startup abc')) ;

pump_until($case->{pty}, sub { $case->{pty}->startup_fired ; }) ;

$case->{pty}->pump(0.05) for 1 .. 10 ;

is($case->{pty}->is_running, 1, 'the text is sent once, the child is still waiting for the rest') ;

syswrite($case->{writer}, 'de') ;

pump_until($case->{pty}, sub { !$case->{pty}->is_running ; }) ;

is(read_file($case->{out}), 'abcde', 'and what follows comes from the user') ;

# a child that is gone

my ($gone_input, $gone_writer) = pipe_pair() ;
my $gone = start_engine({ input => $gone_input, startup => startup_from('send-startup abc') }, 'true') ;

$gone->wait_exit ;

is(pump_until($gone, sub { $gone->startup_fired ; }), 1, 'a startup for a child that has ended still fires') ;
is($gone->pending_input, 0, 'and its text is dropped') ;

# a lot of text, a slow child

my $text = join('', map { chr(65 + $_ % 26) } 0 .. 299999) ;
my $big  = KeyFilter::Startup->new({ cmd => 'send-startup', text => $text }) ;

my ($slow_input, $slow_writer) = pipe_pair() ;

push @writers, $slow_writer ;

my $slow = start_engine({ input => $slow_input, startup => $big }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/slow.ready ; sleep 1 ; head -c 300000 > $dir/slow.out") ;

wait_for_file("$dir/slow.ready") ;

pump_until($slow, sub { $slow->startup_fired ; }) ;

cmp_ok($slow->pending_input, '>', 0, 'a text the child cannot take at once stays pending') ;

pump_until($slow, sub { !$slow->pending_input ; }, 30) ;

is($slow->pending_input, 0, 'and is delivered when the child reads') ;

$slow->wait_exit ;

ok(read_file("$dir/slow.out") eq $text, 'complete and in order') ;

# in a run

my $run = engine_process({ startup => startup_from('startup-delay 100', 'send-startup hello') }, 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 5') ;

is($run->read_all, "ready\nhello", 'a run delivers the startup text to the child') ;
is($run->finish, 0, 'and ends normally') ;

my $cooked = engine_process({ startup => startup_from('startup-delay 100', 'send-startup hello\n') }, 'sh', '-c', 'read x ; echo got:$x') ;

like($cooked->read_all, qr/got:hello\r\n/, 'a shell reads a line sent by a startup') ;
is($cooked->finish, 0, 'and ends') ;

my $commands = engine_process({ startup => startup_from('startup-delay 100', 'send-startup echo one<<Enter>>', 'send-startup echo two<<Enter>>', 'send-startup exit 7<<Enter>>') }, 'sh') ;

my $shell_output = $commands->read_all ;

like($shell_output, qr/one\r\n.*two\r\n/s, 'commands typed by a startup are run in order') ;
is($commands->finish, 7, 'the last one ends the shell') ;

done_testing ;
