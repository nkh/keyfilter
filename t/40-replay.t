#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir     = temp_dir() ;
my $counter = 0 ;
my $script  = "$FindBin::Bin/../keyfilter" ;

sub replay
{
my ($text, %arguments) = @_ ;

my $path = "$dir/out" . ++$counter ;

open(my $output, '>', $path) or die ;

my $replayer = KeyFilter::Replayer->new(text => $text, output => $output, %arguments) ;
my $code     = $replayer->run ;

close $output ;

return { code => $code, output => read_file($path), replayer => $replayer } ;
}

# -----------------------------------------------------------------------------

sub fake_time
{
my ($step) = @_ ;

my $now    = 0 ;
my @sleeps ;

my %fake =
	(
	clock  => sub { return $now ; },
	sleep  => sub { push @sleeps, $_[0] ; $now += defined $step ? $_[0] * $step : $_[0] ; },
	sleeps => \@sleeps,
	) ;

return \%fake ;
}

# -----------------------------------------------------------------------------

sub rounded { return map { sprintf('%.6f', $_) } @_ ; }

# -----------------------------------------------------------------------------

my $header = "# keyfilter-recording 1\n" ;

# the timing of a replay

my $time = fake_time() ;
my $text = $header . "0.100000 O a\n0.500000 I x\n0.500000 O b\n0.500000 O c\n1.250000 O d\n2.000000 X 3\n" ;
my $run  = replay($text, clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{output}, 'abcd', 'the output of a recording is written') ;
is($run->{code}, 3, 'and the exit code of the recording is returned') ;
is_deeply([ rounded(@{$time->{sleeps}}) ], ['0.100000', '0.400000', '0.750000', '0.750000'], 'the replay waits for the time of each event, and for the time of the exit') ;

$time = fake_time() ;
$run  = replay($header . "0.000000 O a\n0.000000 O b\n0.000000 X 0\n", clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{output}, 'ab', 'events at time zero are written') ;
is_deeply($time->{sleeps}, [], 'without waiting') ;

$time = fake_time() ;
$run  = replay($header, clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{output}, '', 'an empty recording writes nothing') ;
is($run->{code}, 0, 'and returns 0') ;
is_deeply($time->{sleeps}, [], 'at once') ;

$time = fake_time() ;
$run  = replay($header . "0.250000 O a\n0.500000 O b\n", clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{code}, 0, 'a recording without an exit code returns 0') ;
is($run->{output}, 'ab', 'and is replayed') ;
is_deeply([ rounded(@{$time->{sleeps}}) ], ['0.250000', '0.250000'], 'up to its last event') ;

$time = fake_time() ;
$run  = replay($header . "1.000000 X 7\n", clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{code}, 7, 'a recording with only an exit code returns it') ;
is_deeply([ rounded(@{$time->{sleeps}}) ], ['1.000000'], 'after the time it was recorded at') ;

my $offset_now = 5000 ;
my @offset_sleeps ;

$run = replay($header . "0.500000 O a\n1.000000 O b\n", clock => sub { return $offset_now ; }, sleep => sub { push @offset_sleeps, $_[0] ; $offset_now += $_[0] ; }) ;

is($run->{output}, 'ab', 'the clock can start anywhere') ;
is_deeply([ rounded(@offset_sleeps) ], ['0.500000', '0.500000'], 'time is counted from the start of the replay') ;

my $now = 0 ;
my @halves ;

$run = replay($header . "1.000000 O a\n", clock => sub { return $now ; }, sleep => sub { push @halves, $_[0] ; $now += $_[0] / 2 ; }) ;

is($run->{output}, 'a', 'a sleep that is cut short is repeated') ;
cmp_ok(scalar @halves, '>', 3, 'as many times as needed') ;
cmp_ok($now, '>=', 1 - 1e-6, 'until the time has come') ;

$time = fake_time() ;
$run  = replay($header . "10800.000000 O late\n10800.500000 X 0\n", clock => $time->{clock}, sleep => $time->{sleep}) ;

is($run->{output}, 'late', 'a long recording is replayed') ;
is_deeply([ rounded(@{$time->{sleeps}}) ], ['10800.000000', '0.500000'], 'with its long waits') ;

# data

my $everything = join('', map { chr } 0 .. 255) ;
my $binary     = $header . '0.000000 O ' . KeyFilter::Recorder::encode($everything) . "\n" ;

is(replay($binary, clock => $time->{clock}, sleep => $time->{sleep})->{output}, $everything, 'every byte value is written unchanged') ;

my $big = $header . '0.000000 O ' . ('0123456789' x 100000) . "\n" ;

is(length replay($big, clock => $time->{clock}, sleep => $time->{sleep})->{output}, 1000000, 'a large output is written completely') ;

my @replayed = replay($header . "0.000000 I typed\n0.000000 O shown\n0.000000 I more\n", clock => $time->{clock}, sleep => $time->{sleep}) ;

is($replayed[0]{output}, 'shown', 'input is not written, only output') ;

is_deeply([ map { $_->{type} } $replayed[0]{replayer}->events ], ['I', 'O', 'I'], 'the events of a recording can be read back') ;
is($replayed[0]{replayer}->exit_code, 0, 'and its exit code') ;

# an output that is gone

pipe(my $gone_read, my $gone_write) or die ;

close $gone_read ;

my $closed = fake_time() ;
my $broken = KeyFilter::Replayer->new(text => $header . "0.000000 O a\n5.000000 O b\n9.000000 X 6\n", output => $gone_write, clock => $closed->{clock}, sleep => $closed->{sleep}) ;

is($broken->run, 6, 'a replay whose reader is gone ends without a signal') ;
cmp_ok(scalar @{$closed->{sleeps}}, '<=', 1, 'and does not wait for the rest') ;

# errors

like(failure_of(sub { KeyFilter::Replayer->new() ; }), qr/\Aa replay needs a recording/, 'a recording is needed') ;
like(failure_of(sub { KeyFilter::Replayer->new(file => "$dir/missing.rec") ; }), qr/\Acannot read the recording '\Q$dir\E\/missing\.rec': No such file or directory/, 'a missing recording is fatal') ;
like(failure_of(sub { KeyFilter::Replayer->new(text => "bad line\n") ; }), qr/\Arecording line 1: invalid event/, 'an invalid recording is fatal and names the line') ;

write_file("$dir/invalid.rec", $header, "0.000000 O a\n", "0.000000 O \\q\n") ;

like(failure_of(sub { KeyFilter::Replayer->new(file => "$dir/invalid.rec") ; }), qr/\A\Q$dir\E\/invalid\.rec: recording line 3: unknown escape/, 'and the file') ;

write_file("$dir/back.rec", $header, "1.000000 O a\n", "0.500000 O b\n") ;

like(failure_of(sub { KeyFilter::Replayer->new(file => "$dir/back.rec") ; }), qr/recording line 3: the time goes back/, 'a recording whose times go back is fatal') ;

# real time

write_file("$dir/real.rec", $header, "0.000000 O first\n", "0.400000 O second\n", "0.600000 X 2\n") ;

open(my $real_output, '>', "$dir/real.out") or die ;

my $began = Time::HiRes::time() ;
my $real  = KeyFilter::Replayer->new(file => "$dir/real.rec", output => $real_output)->run ;
my $took  = Time::HiRes::time() - $began ;

close $real_output ;

is($real, 2, 'a replay in real time returns the exit code') ;
is(read_file("$dir/real.out"), 'firstsecond', 'writes the output') ;
cmp_ok($took, '>=', 0.55, 'and takes the time of the recording') ;
cmp_ok($took, '<', 3, 'and not much more') ;

# a recorded session

my $session = KeyFilter::Recorder->new(file => "$dir/session.rec") ;
my $original = run_engine({ recorder => $session }, 'sh', '-c', 'echo one ; sleep 0.4 ; echo two ; exit 4') ;

open(my $session_output, '>', "$dir/session.out") or die ;

$began = Time::HiRes::time() ;

my $session_code = KeyFilter::Replayer->new(file => "$dir/session.rec", output => $session_output)->run ;

$took = Time::HiRes::time() - $began ;

close $session_output ;

is(read_file("$dir/session.out"), $original->{output}, 'the replay of a real session shows what the session showed') ;
is($session_code, 4, 'and gives the exit code of the session') ;
cmp_ok($took, '>=', 0.35, 'after the same pauses') ;

# the command line

is_deeply(KeyFilter::CLI::parse_arguments(), { command => [] }, 'no argument, no option') ;
is_deeply(KeyFilter::CLI::parse_arguments('--discover'), { command => [], discover => 1 }, '--discover') ;
is_deeply(KeyFilter::CLI::parse_arguments('--replay', 'f.rec'), { command => [], replay => 'f.rec' }, '--replay takes a file') ;
is_deeply(KeyFilter::CLI::parse_arguments('--replay=f.rec'), { command => [], replay => 'f.rec' }, 'also with an equal sign') ;
is_deeply(KeyFilter::CLI::parse_arguments('--record', 'f.rec', '--', 'sh', '-c', 'x y'), { command => ['sh', '-c', 'x y'], record => 'f.rec' }, '--record and a command after the double dash') ;
is_deeply(KeyFilter::CLI::parse_arguments('--record=a=b', 'cmd'), { command => ['cmd'], record => 'a=b' }, 'the value of an option may contain equal signs') ;
is_deeply(KeyFilter::CLI::parse_arguments('sh', '-c', 'echo'), { command => ['sh', '-c', 'echo'] }, 'a command without the double dash') ;
is_deeply(KeyFilter::CLI::parse_arguments('--', '--discover'), { command => ['--discover'] }, 'after the double dash everything is the command') ;
is_deeply(KeyFilter::CLI::parse_arguments('cmd', '--record', 'x'), { command => ['cmd', '--record', 'x'] }, 'after the command everything is for the command') ;
is_deeply(KeyFilter::CLI::parse_arguments('--'), { command => [] }, 'a double dash alone gives no command') ;

my @bad_arguments =
	(
	[['--bogus'], qr/\Aunknown option '--bogus'/],
	[['--replay'], qr/\Aoption '--replay' needs a value/],
	[['--record'], qr/\Aoption '--record' needs a value/],
	[['--discover=1'], qr/\Aoption '--discover' takes no value/],
	[['--discover', 'cmd'], qr/--discover cannot be used/],
	[['--discover', '--record', 'f'], qr/--discover cannot be used/],
	[['--replay', 'f', 'cmd'], qr/--replay does not run a command/],
	[['--replay', 'f', '--record', 'g'], qr/--replay cannot be used with --record/],
	) ;

for my $case (@bad_arguments)
	{
	my ($arguments, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::CLI::parse_arguments(@$arguments) ; }), $pattern, "refused: @$arguments") ;
	}

# keyfilter --record and --replay

my $recorded = "$dir/cli.rec" ;
my $shown    = qx{$^X $script --record $recorded -- sh -c 'echo a ; sleep 0.4 ; echo b ; exit 4' </dev/null} ;

is($shown, "a\r\nb\r\n", 'keyfilter shows the output while it records it') ;
is($? >> 8, 4, 'and returns the exit code') ;

my @cli_events = KeyFilter::Recorder::parse_recording(read_file($recorded)) ;

is($cli_events[-1]{type}, 'X', 'the recording ends with the exit code') ;
is($cli_events[-1]{code}, 4, 'which is the one of the child') ;

$began = Time::HiRes::time() ;

my $again = qx{$^X $script --replay $recorded} ;

$took = Time::HiRes::time() - $began ;

is($again, "a\r\nb\r\n", 'keyfilter --replay shows the same output') ;
is($? >> 8, 4, 'with the same exit code') ;
cmp_ok($took, '>=', 0.35, 'and the same pauses') ;

is(qx{$^X $script --replay=$recorded}, "a\r\nb\r\n", 'the equal sign works on the command line') ;

my $missing = qx{$^X $script --replay $dir/nope.rec 2>&1} ;

like($missing, qr/\Akeyfilter: cannot read the recording '\Q$dir\E\/nope\.rec': No such file or directory\n\z/, 'a missing recording is reported') ;
is($? >> 8, 255, 'with a failure code') ;

write_file("$dir/garbage.rec", "garbage\n") ;

like(qx{$^X $script --replay $dir/garbage.rec 2>&1}, qr/\Akeyfilter: \Q$dir\E\/garbage\.rec: recording line 1: invalid event\n\z/, 'an invalid recording is reported') ;

like(qx{$^X $script --replay $recorded -- echo 2>&1}, qr/\Akeyfilter: --replay does not run a command\n\z/, 'replay does not take a command') ;
is($? >> 8, 1, 'usage errors give 1') ;

like(qx{$^X $script --record $dir/no/such/dir/x.rec -- true 2>&1 </dev/null}, qr/\Akeyfilter: cannot write the recording '\Q$dir\E\/no\/such\/dir\/x\.rec': No such file or directory\n\z/, 'a recording that cannot be written is reported') ;
is($? >> 8, 255, 'with a failure code') ;

like(qx{$^X $script --bogus 2>&1}, qr/\Akeyfilter: unknown option '--bogus'\n\z/, 'an unknown option is reported') ;
like(qx{$^X $script 2>&1 </dev/null}, qr/\AUsage: keyfilter/, 'no command gives the usage') ;
isnt($? >> 8, 0, 'and a failure code') ;

done_testing ;
