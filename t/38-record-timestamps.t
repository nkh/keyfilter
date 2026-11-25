#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir     = temp_dir() ;
my $counter = 0 ;

sub startup_from { return KeyFilter::Startup->new(map { scalar KeyFilter::Command::parse_command($_) } @_) ; }

# -----------------------------------------------------------------------------

sub clock_of
{
my (@times) = @_ ;

my @queue = @times ;

return sub { return @queue ? shift @queue : $times[-1] ; } ;
}

# -----------------------------------------------------------------------------

sub recording
{
my ($clock, $code) = @_ ;

my $path = "$dir/rec" . ++$counter ;
my $rec  = KeyFilter::Recorder->new(file => $path, clock => $clock) ;

$code->($rec) ;

$rec->close ;

return read_file($path) ;
}

# -----------------------------------------------------------------------------

sub events_of { my ($path) = @_ ; return KeyFilter::Recorder::parse_recording(read_file($path)) ; }

# -----------------------------------------------------------------------------

# the time of an event

is(recording(clock_of(100, 100.5, 101.25), sub { $_[0]->record_input('a') ; $_[0]->record_output('b') ; }), "# keyfilter-recording 1\n0.500000 I a\n1.250000 O b\n", 'each event starts with the seconds since the recording was created') ;
is(recording(clock_of(5000.123, 5000.123), sub { $_[0]->record_input('a') ; }), "# keyfilter-recording 1\n0.000000 I a\n", 'whatever the clock says when the recording is created') ;
is(recording(clock_of(0, 123456.789), sub { $_[0]->record_output('a') ; }), "# keyfilter-recording 1\n123456.789000 O a\n", 'a long recording has large times') ;
is(recording(clock_of(0, 0.0000004, 0.0000006, 0.9999996), sub { $_[0]->record_input($_) for 'a', 'b', 'c' ; }), "# keyfilter-recording 1\n0.000000 I a\n0.000001 I b\n1.000000 I c\n", 'times have six decimals, rounded') ;
is(recording(clock_of(0, 1, 1, 1), sub { $_[0]->record_input($_) for 'a', 'b', 'c' ; }), "# keyfilter-recording 1\n1.000000 I a\n1.000000 I b\n1.000000 I c\n", 'events at the same time have the same time') ;
is(recording(clock_of(10, 10.5, 10.2, 11), sub { $_[0]->record_input($_) for 'a', 'b', 'c' ; }), "# keyfilter-recording 1\n0.500000 I a\n0.500000 I b\n1.000000 I c\n", 'a clock that goes back does not make times go back') ;
is(recording(clock_of(0, 1, 2), sub { $_[0]->record_input('') ; $_[0]->record_output(undef) ; $_[0]->record_input('a') ; $_[0]->record_output('b') ; }), "# keyfilter-recording 1\n1.000000 I a\n2.000000 O b\n", 'an empty event does not use the clock') ;
is(recording(clock_of(0), sub { }), "# keyfilter-recording 1\n", 'the header has no time') ;

my $fake = KeyFilter::Recorder->new(file => "$dir/elapsed", clock => clock_of(0, 0.5, 0.25, 3)) ;

is($fake->elapsed, '0.500000', 'elapsed gives the time as it is written') ;
is($fake->elapsed, '0.500000', 'and never goes back') ;
is($fake->elapsed, '3.000000', 'but goes forward') ;

$fake->close ;

my $first = KeyFilter::Recorder::monotonic_seconds() ;
my $next  = KeyFilter::Recorder::monotonic_seconds() ;

cmp_ok($next, '>=', $first, 'the default clock does not go back') ;

# the real clock

my $real = KeyFilter::Recorder->new(file => "$dir/real") ;

$real->record_input('first') ;

Time::HiRes::sleep(0.3) ;

$real->record_output('second') ;
$real->close ;

my @real = events_of("$dir/real") ;

cmp_ok($real[0]{time}, '<', 0.2, 'the first event is soon after the start') ;
cmp_ok($real[1]{time} - $real[0]{time}, '>=', 0.28, 'a pause between events is in the times') ;
cmp_ok($real[1]{time} - $real[0]{time}, '<', 1, 'and is not much longer') ;

my @lines = grep { !/\A#/ } split /\n/, read_file("$dir/real") ;

is((grep { !/\A\d+\.\d{6} [IO] / } @lines), 0, 'every event line starts with a time of six decimals') ;

# reading times

my @read = KeyFilter::Recorder::parse_recording("# header\n0.000000 I a\n12.345678 O b\n12.345678 I c\n100.000001 O d\n") ;

is_deeply([ map { $_->{time} } @read ], [0, 12.345678, 12.345678, 100.000001], 'the time of each event is read') ;
is_deeply([ map { "$_->{type}$_->{data}" } @read ], ['Ia', 'Ob', 'Ic', 'Od'], 'with its type and data') ;

for my $bad ('0.0 I a', '1 I a', '-1.000000 I a', '.500000 I a', '0.000000I a', ' 0.000000 I a', '0.0000001 I a', 'I a', 'x.000000 I a', '0.000000  I a')
	{
	like(failure_of(sub { KeyFilter::Recorder::parse_recording("$bad\n") ; }), qr/\Arecording line 1: invalid event/, "'$bad' is not an event") ;
	}

like(failure_of(sub { KeyFilter::Recorder::parse_recording("1.000000 I a\n0.999999 O b\n") ; }), qr/\Arecording line 2: the time goes back/, 'times that go back are fatal') ;
like(failure_of(sub { KeyFilter::Recorder::parse_recording("# c\n1.000000 I a\n\n# c\n0.500000 O b\n") ; }), qr/\Arecording line 5: the time goes back/, 'and the line is the line of the file') ;
is(scalar(() = KeyFilter::Recorder::parse_recording("1.000000 I a\n1.000000 O b\n")), 2, 'equal times are fine') ;

# in a run

my $early = KeyFilter::Recorder->new(file => "$dir/early") ;

Time::HiRes::sleep(0.3) ;

run_engine({ recorder => $early }, 'echo', 'late') ;

my @early = events_of("$dir/early") ;

cmp_ok($early[0]{time}, '>=', 0.28, 'time counts from the creation of the recording, not from the run') ;

my $gap = KeyFilter::Recorder->new(file => "$dir/gap") ;

run_engine({ recorder => $gap }, 'sh', '-c', 'echo one ; sleep 0.5 ; echo two') ;

my @gap = grep { $_->{type} eq 'O' } events_of("$dir/gap") ;
my ($one) = grep { $gap[$_]{data} =~ /one/ } 0 .. $#gap ;
my ($two) = grep { $gap[$_]{data} =~ /two/ } 0 .. $#gap ;

cmp_ok($gap[$two]{time} - $gap[$one]{time}, '>=', 0.45, 'the time between two outputs of the child is recorded') ;
cmp_ok($gap[$two]{time} - $gap[$one]{time}, '<', 2, 'and is not much longer') ;

my $delayed = KeyFilter::Recorder->new(file => "$dir/delayed") ;
my ($delay_input, $delay_writer) = pipe_pair() ;

my $with_delay = KeyFilter::PTY->new(command => ['sh', '-c', 'stty raw -echo ; head -c 1'], input => $delay_input, output => do { open(my $null, '>', '/dev/null') ; $null }, recorder => $delayed, startup => startup_from('startup-delay 400', 'send-startup x')) ;

$with_delay->run ;

my @delayed = grep { $_->{type} eq 'I' } events_of("$dir/delayed") ;

cmp_ok($delayed[0]{time}, '>=', 0.39, 'the text of a startup is recorded when it is sent') ;
cmp_ok($delayed[0]{time}, '<', 2, 'and not later') ;

my $typed = KeyFilter::Recorder->new(file => "$dir/typed") ;
my ($typed_input, $typed_writer) = pipe_pair() ;
my $engine = start_engine({ input => $typed_input, recorder => $typed }, 'sleep', '10') ;

syswrite($typed_writer, 'a') ;

$engine->forward_input ;

Time::HiRes::sleep(0.4) ;

syswrite($typed_writer, 'b') ;

$engine->forward_input ;

$typed->close ;
$engine->signal('KILL') ;

my @typed = events_of("$dir/typed") ;

is_deeply([ map { $_->{data} } @typed ], ['a', 'b'], 'typed input is recorded as it arrives') ;
cmp_ok($typed[1]{time} - $typed[0]{time}, '>=', 0.38, 'with the pause between the keys') ;

my $busy = KeyFilter::Recorder->new(file => "$dir/busy") ;

run_engine({ recorder => $busy, input_data => "x\n" x 200 }, 'sh', '-c', 'stty raw -echo ; "$0" -e "print qq(line\n) x 20000 ; sleep 0.2 ; print q(end)"', $^X) ;

my @busy = events_of("$dir/busy") ;
my $back = 0 ;

for my $index (1 .. $#busy)
	{
	$back++ if $busy[$index]{time} < $busy[$index - 1]{time} ;
	}

cmp_ok(scalar @busy, '>', 5, 'a busy run has many events') ;
is($back, 0, 'and their times never go back') ;

done_testing ;
