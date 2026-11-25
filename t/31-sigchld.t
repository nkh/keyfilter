#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub fd_count { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; }

# -----------------------------------------------------------------------------

sub kill_group { my ($pty) = @_ ; kill 'KILL', -$pty->pid ; }

# -----------------------------------------------------------------------------

# the exit of the child is noticed even if something else keeps the terminal open

my $started = Time::HiRes::time() ;
my $held    = run_engine({}, 'sh', '-c', 'sleep 20 & echo started ; exit 5') ;

cmp_ok(Time::HiRes::time() - $started, '<', 8, 'run does not wait for a background process that keeps the terminal open') ;
is($held->{code}, 5, 'and returns the exit code of the child') ;
is($held->{output}, "started\r\n", 'with the output of the child') ;

kill_group($held->{pty}) ;

my $signalled = run_engine({}, 'sh', '-c', 'sleep 20 & echo before ; kill -9 $$') ;

is($signalled->{code}, 137, 'a child killed by a signal gives 128 plus the signal, with a background process around') ;
is($signalled->{output}, "before\r\n", 'and its output') ;

kill_group($signalled->{pty}) ;

my $big = run_engine({}, 'sh', '-c', 'sleep 20 & stty raw -echo ; "$0" -e "print q(0123456789) x 20000" ; exit 3', $^X) ;

is($big->{code}, 3, 'a child that writes a lot and ends at once keeps its exit code') ;
is($big->{output}, '0123456789' x 20000, 'and none of its output is lost') ;

kill_group($big->{pty}) ;

my $endless = run_engine({}, 'sh', '-c', 'yes > /dev/tty & sleep 0.3 ; exit 0') ;

is($endless->{code}, 0, 'a background process that never stops writing does not keep run from ending') ;
cmp_ok(length $endless->{output}, '>', 0, 'and what it wrote is forwarded') ;

kill_group($endless->{pty}) ;

# races

my $lost = 0 ;

for (1 .. 40)
	{
	my $quick = run_engine({}, 'sh', '-c', 'echo fast ; exit 3') ;
	
	$lost++ unless $quick->{output} eq "fast\r\n" && $quick->{code} == 3 ;
	}

is($lost, 0, 'a child that ends at once, forty times, loses nothing') ;

my $immediate = 0 ;

for (1 .. 40)
	{
	my $true = run_engine({}, 'true') ;
	
	$immediate++ if defined $true->{code} && $true->{code} == 0 ;
	}

is($immediate, 40, 'a child that does nothing ends well, forty times') ;

# promptness

$started = Time::HiRes::time() ;

my $idle = run_engine({}, 'sh', '-c', 'sleep 0.4 ; exit 1') ;

my $elapsed = Time::HiRes::time() - $started ;

is($idle->{code}, 1, 'an idle child that ends later gives its code') ;
cmp_ok($elapsed, '>=', 0.35, 'not before it ended') ;
cmp_ok($elapsed, '<', 2, 'and soon after') ;

# the engine does not wait for the end of the input

my $open_input = engine_process({}, 'sh', '-c', 'echo bye ; exit 2') ;

is($open_input->finish(10), 2, 'the engine ends with the child, the input does not have to end') ;

# unit level

my $pty = start_engine({}, 'sleep', '0.4') ;

is($pty->child_exited, 0, 'child_exited does nothing while the child lives') ;
is($pty->finished, 0, 'the engine is not finished') ;
ok(!defined $pty->exit_code, 'and there is no exit code') ;

Time::HiRes::sleep(0.7) ;

is($pty->child_exited, 1, 'child_exited reaps a child that ended') ;
is($pty->finished, 1, 'and finishes the engine') ;
is($pty->exit_code, 0, 'with the exit code') ;
is($pty->child_exited, 1, 'calling it again is harmless') ;

is(KeyFilter::PTY->new(command => ['true'])->child_exited, 0, 'child_exited without a child does nothing') ;

my @events ;
my $by_event = KeyFilter::PTY->new(command => ['sh', '-c', 'sleep 0.3 ; exit 4'], on_event => sub { push @events, $_[0] ; }, output => do { open(my $null, '>', '/dev/null') ; $null }) ;

$by_event->spawn ;
$by_event->handle_signal(CHLD => 'C') ;

my $limit = Time::HiRes::time() + 5 ;

$by_event->pump(0.2) until defined $by_event->exit_code || Time::HiRes::time() > $limit ;

is($by_event->exit_code, 4, 'the SIGCHLD signal reaps the child and gives its exit code') ;
is($by_event->finished, 1, 'and finishes the engine') ;
is_deeply(\@events, ['C'], 'through a single child event') ;

$by_event->cleanup ;

my $by_wake = start_engine({}, 'sh', '-c', 'exit 6') ;

Time::HiRes::sleep(0.3) ;

$by_wake->wake('C') ;

cmp_ok($by_wake->pump(1), '>=', 1, 'a child event is handled') ;
is($by_wake->exit_code, 6, 'and gives the code') ;

# signals the user sends to keyfilter go to the child

my %forwarded = (TERM => 143, INT => 130, QUIT => 131, HUP => 129) ;

for my $name (sort keys %forwarded)
	{
	my $engine = engine_process({}, 'sh', '-c', 'echo ready ; sleep 30') ;
	
	$engine->read_until(qr/ready\r\n/) ;
	$engine->signal($name) ;
	
	is($engine->finish(10), $forwarded{$name}, "$name sent to the engine ends the child with the signal") ;
	}

my %handled = (TERM => 9, INT => 8, QUIT => 7, HUP => 6) ;

for my $name (sort keys %handled)
	{
	my $engine = engine_process({}, 'sh', '-c', "trap 'exit $handled{$name}' $name ; echo ready ; sleep 30 & wait") ;
	
	$engine->read_until(qr/ready\r\n/) ;
	$engine->signal($name) ;
	
	is($engine->finish(10), $handled{$name}, "a child that handles $name receives it") ;
	}

my $group = engine_process({}, 'sh', '-c', 'sleep 30 & echo $! ; wait') ;
my ($background) = $group->read_until(qr/\d+\r\n/) =~ /(\d+)/ ;

$group->signal('TERM') ;

is($group->finish(10), 143, 'the shell ends') ;
ok(process_gone($background), 'the signal went to the whole group of the child') ;

# nothing is left behind

{
local $SIG{CHLD} = sub { 1 } ;
local $SIG{INT}  = 'IGNORE' ;
local $SIG{TERM} = 'IGNORE' ;
local $SIG{QUIT} = 'IGNORE' ;
local $SIG{HUP}  = 'IGNORE' ;

my $kept = $SIG{CHLD} ;

run_engine({}, 'true') ;

is($SIG{CHLD}, $kept, 'the SIGCHLD handler is restored when run ends') ;
is($SIG{$_}, 'IGNORE', "the $_ setting is restored when run ends") for qw(INT TERM QUIT HUP) ;
}

{
local $SIG{CHLD} ;
local $SIG{INT}  ;

run_engine({}, 'true') ;

ok(!defined $SIG{CHLD} || $SIG{CHLD} eq 'DEFAULT', 'no handler stays when there was none') ;
ok(!defined $SIG{INT} || $SIG{INT} eq 'DEFAULT', 'and the same for INT') ;
}

SKIP:
	{
	skip 'no /proc', 2 unless -d '/proc/self/fd' ;
	
	run_engine({}, 'true') ;
	
	my $before = fd_count() ;
	
	run_engine({}, 'sh', '-c', 'echo x ; exit 1') for 1 .. 20 ;
	
	is(fd_count(), $before, 'twenty runs leave no descriptor open') ;
	
	my $ended = run_engine({}, 'true') ;
	
	is(waitpid($ended->{pty}->pid, POSIX::WNOHANG()), -1, 'the child is reaped') ;
	}

# the terminal of the user comes back when the child ends by itself

my ($terminal, $slave) = new_terminal() ;

my $before = termios_of($slave) ;
my $tty    = engine_process({ tty_input => $slave }, 'sh', '-c', 'sleep 20 & echo ready ; exit 7') ;

like(read_until($tty->{output}, qr/ready\r\n/), qr/ready/, 'the engine runs on the terminal of the user') ;
is($tty->finish(10), 7, 'and ends with the code of the child') ;
is_deeply(termios_of($slave), $before, 'the terminal of the user is restored') ;

done_testing ;
