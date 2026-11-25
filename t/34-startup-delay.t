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

my @engines_inputs ;

sub engine
{
my (%arguments) = @_ ;

my ($input, $writer) = pipe_pair() ;

push @engines_inputs, $writer ;

open(my $null, '>', '/dev/null') or die ;

return KeyFilter::PTY->new(command => $arguments{command} // ['sleep', '10'], input => $input, output => $null, %arguments) ;
}

# -----------------------------------------------------------------------------

# the delay of a startup

is(KeyFilter::Startup->new()->delay_ms, 0, 'without commands there is no delay') ;
is(startup_from('startup-delay 500')->delay_ms, 500, 'a delay is read from startup-delay') ;
is(startup_from('startup-delay 0')->delay_ms, 0, 'the delay can be zero') ;
is(startup_from('startup-delay 86400000')->delay_ms, 86400000, 'and very long') ;
is(startup_from('startup-delay 100', 'startup-delay 700')->delay_ms, 700, 'the last startup-delay wins') ;
is(startup_from('startup-delay 700', 'startup-delay 100')->delay_ms, 100, 'whatever its value') ;
is(startup_from('startup-delay 700', 'startup-delay 0')->delay_ms, 0, 'even zero') ;
is(startup_from('send-startup make\n')->delay_ms, 0, 'send-startup alone has no delay') ;
is(startup_from('send-startup a', 'startup-delay 250', 'send-startup b')->delay_ms, 250, 'the place of the delay among the other commands does not matter') ;
is(startup_from('startup-delay 250', 'send-startup a')->delay_ms, 250, 'before them') ;
is(startup_from('send-startup a', 'startup-delay 250')->delay_ms, 250, 'or after them') ;

isa_ok(KeyFilter::Startup->new(), 'KeyFilter::Startup') ;

for my $line ('block a', 'map a=b', 'unblock a', 'send abc', 'toggle gaming', 'include x.profile', 'profile vim')
	{
	my ($name) = $line =~ /\A(\S+)/ ;
	
	like(failure_of(sub { startup_from($line) ; }), qr/not a startup command '$name'/, "$name is not a startup command") ;
	}

like(failure_of(sub { KeyFilter::Startup->new('startup-delay 5') ; }), qr/not a startup command ''/, 'a command must be a parsed command, not text') ;
like(failure_of(sub { KeyFilter::Startup->new(undef) ; }), qr/not a startup command ''/, 'undef is not a command') ;
like(failure_of(sub { KeyFilter::Startup->new({}) ; }), qr/not a startup command ''/, 'and neither is an empty hash') ;

# the timer of an engine

my @fired ;
my $began ;

my $pty = engine(startup => startup_from('startup-delay 300'), on_startup => sub { push @fired, Time::HiRes::time() ; }) ;

is($pty->startup_fired, 0, 'a startup has not fired at the start') ;
ok(!defined $pty->startup_remaining, 'and has no time left before the child exists') ;

$began = Time::HiRes::time() ;

$pty->spawn ;

my $remaining = $pty->startup_remaining ;

cmp_ok($remaining, '>', 0.2, 'after the spawn nearly the whole delay is left') ;
cmp_ok($remaining, '<=', 0.3, 'and not more than the delay') ;

is($pty->pump(0), 0, 'pump does not fire it before the delay') ;
is_deeply(\@fired, [], 'and nothing is called') ;

my $limit = Time::HiRes::time() + 5 ;

$pty->pump(0.05) until @fired || Time::HiRes::time() > $limit ;

is(scalar @fired, 1, 'the startup fires') ;

my $waited = $fired[0] - $began ;

cmp_ok($waited, '>=', 0.29, 'not before its delay') ;
cmp_ok($waited, '<', 1, 'and soon after') ;
is($pty->startup_fired, 1, 'and is remembered as fired') ;
ok(!defined $pty->startup_remaining, 'with no time left to wait') ;

$pty->pump(0.4) ;

is(scalar @fired, 1, 'it fires once') ;

$pty->signal('KILL') ;

# the callback is given the startup

my $startup = startup_from('startup-delay 0') ;
my @given ;
my $zero = engine(startup => $startup, on_startup => sub { push @given, $_[0] ; }) ;

$zero->spawn ;

is($zero->pump(0), 1, 'a zero delay fires at the first pump') ;
is($given[0], $startup, 'and the callback receives the startup') ;
is($zero->pump(0), 0, 'only once') ;

$zero->signal('KILL') ;

# without a startup

my $plain = engine(on_startup => sub { die "must not be called\n" ; }) ;

$plain->spawn ;

ok(!defined $plain->startup_remaining, 'no startup, no time to wait') ;
is($plain->pump(0.3), 0, 'pump waits for its own timeout only') ;
is($plain->startup_fired, 0, 'and nothing fires') ;

$plain->signal('KILL') ;

my $silent = engine(startup => startup_from('startup-delay 0')) ;

$silent->spawn ;

is($silent->pump(0), 1, 'a startup without a callback is fine') ;

$silent->signal('KILL') ;

# waiting is done by the select, not by polling

my @late ;
my $waiting = engine(startup => startup_from('startup-delay 500'), on_startup => sub { push @late, Time::HiRes::time() ; }) ;

$waiting->spawn ;

my $started = Time::HiRes::time() ;

is($waiting->pump(10), 1, 'a long pump returns when the startup fires') ;

my $took = Time::HiRes::time() - $started ;

cmp_ok($took, '>=', 0.45, 'after the delay') ;
cmp_ok($took, '<', 2, 'and not after the timeout of the pump') ;

$waiting->signal('KILL') ;

my $short = engine(startup => startup_from('startup-delay 600'), on_startup => sub { push @late, Time::HiRes::time() ; }) ;

$short->spawn ;

$started = Time::HiRes::time() ;

is($short->pump(0.2), 0, 'a short pump gives up at its own timeout') ;

$took = Time::HiRes::time() - $started ;

cmp_ok($took, '>=', 0.15, 'after waiting for it') ;
cmp_ok($took, '<', 0.5, 'and not for the startup') ;
is($short->startup_fired, 0, 'the startup is still waiting') ;

is($short->pump(5), 1, 'and fires in a later pump') ;

$short->signal('KILL') ;

# the delay counts from the spawn

my @after_spawn ;
my $early = engine(startup => startup_from('startup-delay 300'), on_startup => sub { push @after_spawn, Time::HiRes::time() ; }) ;

Time::HiRes::sleep(0.5) ;

$early->spawn ;

my $spawned = Time::HiRes::time() ;

is($early->pump(0), 0, 'time before the spawn does not count') ;

$early->pump(5) ;

cmp_ok($after_spawn[0] - $spawned, '>=', 0.28, 'the delay starts at the spawn') ;

$early->signal('KILL') ;

# other events do not move the startup

my @busy ;
my ($busy_input, $busy_writer) = pipe_pair() ;
my $busy = KeyFilter::PTY->new(command => ['sleep', '10'], input => $busy_input, output => do { open(my $null, '>', '/dev/null') ; $null }, startup => startup_from('startup-delay 400'), on_startup => sub { push @busy, Time::HiRes::time() ; }) ;

$busy->spawn ;

$began = Time::HiRes::time() ;

until (@busy || Time::HiRes::time() - $began > 5)
	{
	syswrite($busy_writer, 'x') ;
	
	$busy->pump(0.02) ;
	}

cmp_ok($busy[0] - $began, '>=', 0.39, 'input arriving all the time does not make it early') ;
cmp_ok($busy[0] - $began, '<', 1.2, 'or late') ;

$busy->signal('KILL') ;

# independent timers

my @order ;
my $slow = engine(startup => startup_from('startup-delay 500'), on_startup => sub { push @order, 'slow' ; }) ;
my $fast = engine(startup => startup_from('startup-delay 100'), on_startup => sub { push @order, 'fast' ; }) ;

$slow->spawn ;
$fast->spawn ;

$limit = Time::HiRes::time() + 5 ;

while (@order < 2 && Time::HiRes::time() < $limit)
	{
	$slow->pump(0.01) ;
	$fast->pump(0.01) ;
	}

is_deeply(\@order, ['fast', 'slow'], 'each engine has its own timer') ;

$slow->signal('KILL') ;
$fast->signal('KILL') ;

like(failure_of(sub { my $e = engine(startup => startup_from('startup-delay 0'), on_startup => sub { die "boom\n" ; }) ; $e->spawn ; $e->pump(0) ; }), qr/\Aboom/, 'an error in the callback is not hidden') ;

# in a run

my $run_start = Time::HiRes::time() ;
my @in_run ;

my $run = run_engine({ startup => startup_from('startup-delay 200'), on_startup => sub { push @in_run, Time::HiRes::time() ; } }, 'sh', '-c', 'sleep 0.7 ; echo done') ;

is($run->{code}, 0, 'a run with a startup ends normally') ;
is(scalar @in_run, 1, 'the startup fired during the run') ;
cmp_ok($in_run[0] - $run_start, '>=', 0.19, 'after its delay') ;
cmp_ok($in_run[0] - $run_start, '<', 0.7, 'while the child was still running') ;
is($run->{pty}->startup_fired, 1, 'and is remembered') ;

my @never ;
my $ended = Time::HiRes::time() ;

my $quick = run_engine({ startup => startup_from('startup-delay 60000'), on_startup => sub { push @never, 1 ; } }, 'true') ;

cmp_ok(Time::HiRes::time() - $ended, '<', 5, 'a long delay does not keep the engine from ending with its child') ;
is_deeply(\@never, [], 'and the startup never fires') ;
is($quick->{pty}->startup_fired, 0, 'and is not marked as fired') ;
is($quick->{code}, 0, 'the exit code is the one of the child') ;

done_testing ;
