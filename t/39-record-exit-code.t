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

sub events_of { my ($path) = @_ ; return KeyFilter::Recorder::parse_recording(read_file($path)) ; }

# -----------------------------------------------------------------------------

sub recorded_run
{
my ($arguments, @command) = @_ ;

my $path = "$dir/run" . ++$counter ;
my $rec  = KeyFilter::Recorder->new(file => $path) ;
my $run  = run_engine({ recorder => $rec, %$arguments }, @command) ;

return ($run, $path) ;
}

# -----------------------------------------------------------------------------

# the exit event

my $path = "$dir/unit" ;
my $rec  = KeyFilter::Recorder->new(file => $path, clock => clock_of(1, 1.1, 1.2, 1.3, 1.4)) ;

$rec->record_input('a') ;
$rec->record_output('b') ;
$rec->record_exit(3) ;
$rec->close ;

is(read_file($path), "# keyfilter-recording 1\n0.100000 I a\n0.200000 O b\n0.300000 X 3\n", 'the exit code is the last line, with its time') ;

$rec = KeyFilter::Recorder->new(file => $path, clock => clock_of(0, 1, 2, 3, 4)) ;

$rec->record_exit(0) ;
$rec->record_exit(1) ;
$rec->record_input('late') ;
$rec->record_output('late') ;
$rec->close ;

is(read_file($path), "# keyfilter-recording 1\n1.000000 X 0\n", 'the exit code is recorded once and nothing comes after it') ;

for my $code (0, 1, 42, 127, 128, 255)
	{
	my $each = KeyFilter::Recorder->new(file => $path, clock => clock_of(0)) ;
	
	$each->record_exit($code) ;
	$each->close ;
	
	is(read_file($path), "# keyfilter-recording 1\n0.000000 X $code\n", "exit code $code") ;
	}

for my $bad (-1, 256, 1000, 'abc', '1.5', '', ' 3', '3 ', '0x10')
	{
	my $recorder = KeyFilter::Recorder->new(file => $path, clock => clock_of(0)) ;
	
	like(failure_of(sub { $recorder->record_exit($bad) ; }), qr/\Ainvalid exit code '\Q$bad\E'/, "'$bad' is not an exit code") ;
	
	$recorder->close ;
	
	is(read_file($path), "# keyfilter-recording 1\n", 'and nothing is written') ;
	}

my $undefined = KeyFilter::Recorder->new(file => $path) ;

like(failure_of(sub { $undefined->record_exit(undef) ; }), qr/\Ainvalid exit code ''/, 'undef is not an exit code') ;

$undefined->close ;

my $closed = KeyFilter::Recorder->new(file => $path, clock => clock_of(0)) ;

$closed->close ;
$closed->record_exit(1) ;

is(read_file($path), "# keyfilter-recording 1\n", 'nothing is written to a closed recording') ;

open(my $handle, '>', "$dir/handle") or die ;

my $to_handle = KeyFilter::Recorder->new(handle => $handle, clock => clock_of(0, 2)) ;

$to_handle->record_exit(9) ;
$to_handle->close ;
close $handle ;

is(read_file("$dir/handle"), "# keyfilter-recording 1\n2.000000 X 9\n", 'the exit code goes to a handle too') ;

# reading it

my @events = KeyFilter::Recorder::parse_recording("# header\n0.000000 I a\n0.500000 O b\n1.250000 X 3\n") ;

is_deeply([ map { $_->{type} } @events ], ['I', 'O', 'X'], 'the exit event is read with the others') ;
is($events[2]{code}, 3, 'with its code') ;
is($events[2]{time}, 1.25, 'and its time') ;
ok(!exists $events[2]{data}, 'it has no data') ;
is(KeyFilter::Recorder::exit_code_of(@events), 3, 'the exit code of a recording is the one of its exit event') ;
is(KeyFilter::Recorder::exit_code_of(@events[0, 1]), undef, 'a recording without an exit event has no exit code') ;
is(KeyFilter::Recorder::exit_code_of(), undef, 'nor has an empty one') ;

for my $code (0, 255)
	{
	is(KeyFilter::Recorder::exit_code_of(KeyFilter::Recorder::parse_recording("0.000000 X $code\n")), $code, "exit code $code is read") ;
	}

my %bad_exits =
	(
	"0.000000 X\n"        => qr/\Arecording line 1: invalid exit code/,
	"0.000000 X abc\n"    => qr/invalid exit code/,
	"0.000000 X -1\n"     => qr/invalid exit code/,
	"0.000000 X 256\n"    => qr/invalid exit code/,
	"0.000000 X 1 2\n"    => qr/invalid exit code/,
	"0.000000 X  3\n"     => qr/invalid exit code/,
	"0.000000 X 3\n0.000000 I a\n"  => qr/\Arecording line 2: an event after the exit code/,
	"0.000000 X 3\n0.000000 O a\n"  => qr/\Arecording line 2: an event after the exit code/,
	"0.000000 X 3\n1.000000 X 3\n"  => qr/\Arecording line 2: an event after the exit code/,
	"# c\n0.000000 X 3\n\n0.5 I a\n" => qr/\Arecording line 4: invalid event/,
	"1.000000 I a\n0.500000 X 3\n"  => qr/\Arecording line 2: the time goes back/,
	) ;

for my $text (sort keys %bad_exits)
	{
	(my $shown = $text) =~ s/\n/|/g ;
	
	like(failure_of(sub { KeyFilter::Recorder::parse_recording($text) ; }), $bad_exits{$text}, "refused: $shown") ;
	}

# a recorded run

for my $code (0, 1, 5, 42, 255)
	{
	my ($run, $file) = recorded_run({}, 'sh', '-c', "echo before ; exit $code") ;
	
	my @recorded = events_of($file) ;
	
	is(KeyFilter::Recorder::exit_code_of(@recorded), $code, "the exit code $code of the child is recorded") ;
	is($run->{code}, $code, 'and is the exit code of the run') ;
	is((grep { $_->{type} eq 'X' } @recorded), 1, 'once') ;
	is($recorded[-1]{type}, 'X', 'as the last event') ;
	}

for my $case (['KILL', 137], ['TERM', 143], ['INT', 130], ['HUP', 129])
	{
	my ($name, $code) = @$case ;
	my ($run, $file)  = recorded_run({}, 'sh', '-c', "kill -$name \$\$") ;
	
	is(KeyFilter::Recorder::exit_code_of(events_of($file)), $code, "a child killed by $name is recorded as $code") ;
	}

my ($true, $true_file) = recorded_run({}, 'true') ;

is(KeyFilter::Recorder::exit_code_of(events_of($true_file)), 0, 'a command that does nothing is recorded too') ;

my ($false, $false_file) = recorded_run({}, 'false') ;

is(KeyFilter::Recorder::exit_code_of(events_of($false_file)), 1, 'and so is one that fails') ;

# the exit comes after everything else

my ($loud, $loud_file) = recorded_run({}, 'sh', '-c', 'stty raw -echo ; "$0" -e "print q(0123456789) x 20000" ; exit 3', $^X) ;

my @loud    = events_of($loud_file) ;
my $output  = join('', map { $_->{data} } grep { $_->{type} eq 'O' } @loud) ;

is($output, '0123456789' x 20000, 'all the output is recorded') ;
is($loud[-1]{type}, 'X', 'before the exit event, which is the last') ;
is($loud[-1]{code}, 3, 'with the code') ;
is((grep { $_->{type} eq 'X' } @loud), 1, 'and only one') ;

my ($echo, $echo_file) = recorded_run({ input_data => "hello\n" }, 'cat') ;

my @echo = events_of($echo_file) ;

is_deeply([ map { $_->{type} } grep { $_->{type} ne 'O' } @echo ], ['I', 'I', 'X'], 'input, the end of the input and the exit code are in order') ;
is($echo[-1]{code}, 0, 'cat ends with 0') ;

my $started = KeyFilter::Recorder->new(file => "$dir/startup") ;
my ($startup_input, $startup_writer) = pipe_pair() ;

KeyFilter::PTY->new(command => ['sh', '-c', 'read x ; exit 4'], input => $startup_input, output => do { open(my $null, '>', '/dev/null') ; $null }, recorder => $started, startup => startup_from('send-startup go\n'))->run ;

my @startup = events_of("$dir/startup") ;

is_deeply([ map { $_->{type} } grep { $_->{type} ne 'O' } @startup ], ['I', 'X'], 'the text of a startup comes before the exit code') ;
is($startup[-1]{type}, 'X', 'which is the last event') ;
is($startup[-1]{code}, 4, 'whose code is the one of the child') ;

# the time of the exit

my $began = KeyFilter::Recorder->new(file => "$dir/slow") ;

run_engine({ recorder => $began }, 'sh', '-c', 'echo x ; sleep 0.5 ; exit 2') ;

my @slow = events_of("$dir/slow") ;

cmp_ok($slow[-1]{time}, '>=', 0.45, 'the exit is recorded when the child ends') ;
cmp_ok($slow[-1]{time}, '<', 2.5, 'and not later') ;

my $background = KeyFilter::Recorder->new(file => "$dir/background") ;
my $held       = run_engine({ recorder => $background }, 'sh', '-c', 'sleep 20 & echo started ; exit 5') ;

kill 'KILL', -$held->{pty}->pid ;

my @held = events_of("$dir/background") ;

is($held[-1]{code}, 5, 'a background process that keeps the terminal does not change the exit code') ;
cmp_ok($held[-1]{time}, '<', 8, 'or delay it') ;

# when there is no exit

my $broken = KeyFilter::Recorder->new(file => "$dir/broken") ;
my $failed = run_engine({ recorder => $broken }, 'no-such-command-xyz') ;

like($failed->{error}, qr/cannot execute/, 'a command that cannot run fails') ;
is(read_file("$dir/broken"), "# keyfilter-recording 1\n", 'and its recording has no exit code') ;

my $filter_fails = KeyFilter::Recorder->new(file => "$dir/filter") ;
my $failing      = run_engine({ recorder => $filter_fails, input_data => "abc\n", filter => sub { die "boom\n" ; } }, 'sleep', '5') ;

kill 'KILL', -$failing->{pty}->pid if defined $failing->{pty}->pid ;

is(KeyFilter::Recorder::exit_code_of(events_of("$dir/filter")), undef, 'a run that fails in the middle has no exit code either') ;

# every recording of a run is complete

my $incomplete = 0 ;

for my $command (['echo', 'a'], ['true'], ['false'], ['sh', '-c', 'exit 9'], ['sh', '-c', 'printf "a\nb\n"'], ['cat'])
	{
	my ($run, $file) = recorded_run({ input_data => "x\n" }, @$command) ;
	
	my @recorded = events_of($file) ;
	
	$incomplete++ unless defined KeyFilter::Recorder::exit_code_of(@recorded) && $recorded[-1]{type} eq 'X' && $recorded[-1]{code} == $run->{code} ;
	}

is($incomplete, 0, 'every recording of a run ends with the exit code that run returned') ;

done_testing ;
