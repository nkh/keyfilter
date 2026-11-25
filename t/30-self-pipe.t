#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Scalar::Util () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @quiet_inputs ;

sub engine
{
my (%arguments) = @_ ;

my ($input, $writer) = pipe_pair() ;

push @quiet_inputs, $writer ;

return KeyFilter::PTY->new(command => ['true'], input => $input, %arguments) ;
}

# -----------------------------------------------------------------------------

sub fd_count { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; }

# -----------------------------------------------------------------------------

# wake and drain

my $engine = engine() ;

is($engine->drain_events, '', 'a new engine has no events') ;

$engine->wake('a') ;

is($engine->drain_events, 'a', 'a wake byte is read back') ;
is($engine->drain_events, '', 'and only once') ;

$engine->wake($_) for split //, 'xyz' ;

is($engine->drain_events, 'xyz', 'events come back in the order they were sent') ;

$engine->wake($_) for ("\0", "\xff", ' ', "\n") ;

is($engine->drain_events, "\0\xff \n", 'any byte can be an event') ;

is($engine->wake('q'), undef, 'wake returns nothing') ;

$engine->drain_events ;

# a full pipe never blocks

my $start = Time::HiRes::time() ;

$engine->wake('F') for 1 .. 200000 ;

cmp_ok(Time::HiRes::time() - $start, '<', 5, 'waking a full pipe does not block') ;

my $flood = $engine->drain_events ;

cmp_ok(length $flood, '>=', 1000, 'the pipe kept what fits') ;
cmp_ok(length $flood, '<=', 200000, 'and no more than was sent') ;
is($flood, 'F' x length $flood, 'and the content is intact') ;

$engine->wake('G') ;

is($engine->drain_events, 'G', 'after draining the pipe works again') ;

# events and pump

my @received ;
my $watched = engine(on_event => sub { push @received, $_[0] ; }) ;

is($watched->pump(0), 0, 'pump without events returns 0') ;
is_deeply(\@received, [], 'and calls nothing') ;

$watched->wake('X') ;

is($watched->pump(0), 1, 'pump returns the number of events') ;
is_deeply(\@received, ['X'], 'and gives each event to on_event') ;

@received = () ;

$watched->wake($_) for split //, 'ABC' ;

is($watched->pump(0), 3, 'several events are counted') ;
is_deeply(\@received, ['A', 'B', 'C'], 'and given in order') ;

is($watched->pump(0), 0, 'an event is handled once') ;

my $quiet = engine() ;

$quiet->wake('?') ;

is($quiet->pump(0), 1, 'an event nobody listens to is accepted') ;

my $dies = engine(on_event => sub { die "boom\n" ; }) ;

$dies->wake('!') ;

like(failure_of(sub { $dies->pump(0) ; }), qr/\Aboom/, 'an error in on_event is not hidden') ;

# signals

my @signalled ;
my $signals = engine(on_event => sub { push @signalled, $_[0] ; }) ;

$signals->handle_signal(USR1 => 'U') ;

kill 'USR1', $$ ;

is($signals->pump(0), 1, 'a signal that arrived before pump is not lost') ;
is_deeply(\@signalled, ['U'], 'and becomes its event') ;

@signalled = () ;

my $began = Time::HiRes::time() ;

if (fork() == 0)
	{
	Time::HiRes::sleep(0.4) ;
	
	kill 'USR1', getppid() ;
	
	POSIX::_exit(0) ;
	}

is($signals->pump(10), 1, 'a signal that arrives while pump waits wakes it up') ;

my $waited = Time::HiRes::time() - $began ;

cmp_ok($waited, '>=', 0.3, 'not before the signal') ;
cmp_ok($waited, '<', 3, 'and long before the timeout') ;
is_deeply(\@signalled, ['U'], 'with the right event') ;

wait ;

@signalled = () ;

$signals->handle_signal(USR2 => 'V') ;

kill 'USR2', $$ ;
kill 'USR1', $$ ;

$signals->pump(1) ;

is_deeply([ sort @signalled ], ['U', 'V'], 'several signals give several events') ;

@signalled = () ;

$signals->handle_signal(ALRM => 'A') ;

$began = Time::HiRes::time() ;

alarm 1 ;

is($signals->pump(10), 1, 'an alarm wakes pump') ;
cmp_ok(Time::HiRes::time() - $began, '<', 4, 'after about a second') ;
is_deeply(\@signalled, ['A'], 'as an event') ;

@signalled = () ;

if (fork() == 0)
	{
	for (1 .. 10)
		{
		Time::HiRes::sleep(0.05) ;
		
		kill 'USR1', getppid() ;
		}
	
	POSIX::_exit(0) ;
	}

my $limit = Time::HiRes::time() + 10 ;

while (@signalled < 10 && Time::HiRes::time() < $limit)
	{
	$signals->pump(1) ;
	}

wait ;

is(scalar @signalled, 10, 'signals sent one after the other are all seen') ;

$signals->restore_signals ;

# restoring signals

$SIG{USR1} = 'IGNORE' ;
$SIG{USR2} = sub { 1 } ;
delete $SIG{WINCH} ;

my $first = engine() ;

$first->handle_signal(USR1 => 'a') ;
$first->handle_signal(USR2 => 'b') ;
$first->handle_signal(WINCH => 'c') ;

isnt($SIG{USR1}, 'IGNORE', 'a handler is installed') ;

$first->handle_signal(USR1 => 'd') ;
$first->restore_signals ;

is($SIG{USR1}, 'IGNORE', 'the previous setting is restored, even if the handler was installed twice') ;
is(ref $SIG{USR2}, 'CODE', 'a previous handler is restored') ;
ok(!defined $SIG{WINCH} || $SIG{WINCH} eq 'DEFAULT', 'no previous setting gives the default') ;

$first->restore_signals ;

is($SIG{USR1}, 'IGNORE', 'restoring twice changes nothing') ;

$SIG{USR1} = 'DEFAULT' ;
$SIG{USR2} = 'DEFAULT' ;

# lifetime

my $weak ;

{
my $short = engine() ;

$weak = $short ;

Scalar::Util::weaken($weak) ;

$short->handle_signal(USR1 => 'z') ;
}

ok(!defined $weak, 'an installed handler does not keep the engine alive') ;

$SIG{USR1} = 'IGNORE' ;

{
my $gone = engine() ;

$gone->handle_signal(USR1 => 'z') ;

undef $gone ;
}

kill 'USR1', $$ ;

pass('a signal that arrives after the engine is gone does nothing') ;

$SIG{USR1} = 'DEFAULT' ;

# independence

my @one ;
my @two ;
my $left  = engine(on_event => sub { push @one, $_[0] ; }) ;
my $right = engine(on_event => sub { push @two, $_[0] ; }) ;

$left->wake('L') ;
$right->wake('R') ;

$left->pump(0) ;
$right->pump(0) ;

is_deeply([\@one, \@two], [['L'], ['R']], 'engines have their own events') ;

# descriptors

SKIP:
	{
	skip 'no /proc', 5 unless -d '/proc/self/fd' ;
	
	my $before = fd_count() ;
	
	my @many = map { engine() } 1 .. 20 ;
	
	is(fd_count(), $before + 80, 'an engine uses two descriptors for its events (and the test two for its input)') ;
	
	$_->cleanup for @many ;
	splice(@quiet_inputs, -20) ;
	
	is(fd_count(), $before + 20, 'cleanup closes the descriptors of the events, the inputs stay') ;
	
	$many[0]->wake('x') ;
	
	is($many[0]->drain_events, '', 'an engine that was cleaned up has no events') ;
	is($many[0]->cleanup, $many[0], 'cleanup can be called twice') ;
	
	my $program = 'opendir(my $d, "/proc/self/fd") or die ; print join(" ", sort { $a <=> $b } grep { /^\d+$/ && $_ != fileno($d) } readdir $d), "\n"' ;
	my $child   = run_engine({}, $^X, '-e', $program) ;
	
	is($child->{output}, "0 1 2\r\n", 'the descriptors of the events are not inherited by the child') ;
	}

done_testing ;
