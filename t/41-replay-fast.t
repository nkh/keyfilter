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
my $script  = "$FindBin::Bin/../keyfilter" ;
my $header  = "# keyfilter-recording 1\n" ;

sub replay
{
my ($text, %arguments) = @_ ;

my $path = "$dir/out" . ++$counter ;

open(my $output, '>', $path) or die ;

my $now    = 0 ;
my $sleeps = 0 ;

my $replayer = KeyFilter::Replayer->new(text => $text, output => $output, clock => sub { return $now ; }, sleep => sub { $sleeps++ ; $now += $_[0] ; }, %arguments) ;
my $code     = $replayer->run ;

close $output ;

return { code => $code, output => read_file($path), sleeps => $sleeps, now => $now } ;
}

# -----------------------------------------------------------------------------

# fast means no waiting

my $text = $header . "0.100000 O a\n0.500000 I x\n0.500000 O b\n1.250000 O c\n7200.000000 O d\n7200.500000 X 3\n" ;

my $timed = replay($text) ;
my $fast  = replay($text, fast => 1) ;

is($fast->{sleeps}, 0, 'a fast replay never waits') ;
is($fast->{now}, 0, 'and no time passes') ;
cmp_ok($timed->{sleeps}, '>', 0, 'a timed replay does wait') ;
cmp_ok($timed->{now}, '>=', 7200.5 - 1e-6, 'for the whole time of the recording') ;
is($fast->{output}, 'abcd', 'a fast replay writes the output') ;
is($fast->{output}, $timed->{output}, 'which is the output of a timed replay') ;
is($fast->{code}, 3, 'and returns the exit code') ;
is($fast->{code}, $timed->{code}, 'the same as a timed replay') ;

is(replay($text, fast => 0)->{sleeps}, 5, 'fast is off by default and when it is false') ;
is(replay($text, fast => undef)->{sleeps}, 5, 'also when it is undefined') ;
is(replay($text, fast => 1)->{sleeps}, 0, 'and on when it is true') ;
is(replay($text, fast => 'yes')->{sleeps}, 0, 'whatever true is') ;

is(replay($header, fast => 1)->{code}, 0, 'a fast replay of an empty recording returns 0') ;
is(replay($header . "0.000000 O a\n99999.000000 O b\n", fast => 1)->{code}, 0, 'a fast replay of a recording without an exit code returns 0') ;
is(replay($header . "5.000000 X 9\n", fast => 1)->{code}, 9, 'and of a recording with only an exit code returns it') ;
is(replay($header . "0.000000 I a\n1.000000 I b\n", fast => 1)->{output}, '', 'input is not written') ;

my $everything = join('', map { chr } 0 .. 255) ;

is(replay($header . '3600.000000 O ' . KeyFilter::Recorder::encode($everything) . "\n", fast => 1)->{output}, $everything, 'every byte value is written unchanged') ;

# any recording gives the same output, fast or not

srand(99) ;

my $different = 0 ;

for my $round (1 .. 60)
	{
	my $now    = 0 ;
	my $lines  = '' ;
	my $expect = '' ;
	
	for (1 .. 1 + int rand 30)
		{
		$now += rand 5 ;
		
		my $data = join('', map { chr int rand 256 } 1 .. 1 + int rand 20) ;
		my $type = rand() < 0.3 ? 'I' : 'O' ;
		
		$lines  .= sprintf('%.6f', $now) . " $type " . KeyFilter::Recorder::encode($data) . "\n" ;
		$expect .= $data if $type eq 'O' ;
		}
	
	my $code = int rand 256 ;
	
	$lines .= sprintf('%.6f', $now + 1) . " X $code\n" ;
	
	my $one = replay($header . $lines, fast => 1) ;
	my $two = replay($header . $lines) ;
	
	$different++ unless $one->{output} eq $expect && $two->{output} eq $expect && $one->{code} == $code && $two->{code} == $code && $one->{sleeps} == 0 ;
	}

is($different, 0, 'sixty random recordings give the same output and exit code, with and without waiting') ;

# a large recording is quick

my $big = $header . '0.000000 O ' . ('0123456789' x 100000) . "\n" . "1.000000 X 0\n" ;
my $began = Time::HiRes::time() ;
my $large = replay($big, fast => 1) ;

is(length $large->{output}, 1000000, 'a large recording is replayed completely') ;
cmp_ok(Time::HiRes::time() - $began, '<', 5, 'and quickly') ;

my $many = $header . join('', map { sprintf('%.6f', $_ / 100) . " O line $_\\n\n" } 1 .. 20000) . "300.000000 X 0\n" ;

$began = Time::HiRes::time() ;

my $lots = replay($many, fast => 1) ;

is($lots->{output}, join('', map { "line $_\n" } 1 .. 20000), 'a recording of twenty thousand events is replayed in order') ;
cmp_ok(Time::HiRes::time() - $began, '<', 5, 'and quickly') ;

# an output that is gone

pipe(my $gone_read, my $gone_write) or die ;

close $gone_read ;

my $broken = KeyFilter::Replayer->new(text => $header . "0.000000 O a\n5.000000 O b\n9.000000 X 6\n", output => $gone_write, fast => 1) ;

is($broken->run, 6, 'a fast replay whose reader is gone ends with the exit code') ;

# a recorded session

my $session = KeyFilter::Recorder->new(file => "$dir/session.rec") ;
my $original = run_engine({ recorder => $session }, 'sh', '-c', 'echo one ; sleep 0.3 ; echo two ; exit 5') ;

open(my $session_output, '>', "$dir/session.out") or die ;

$began = Time::HiRes::time() ;

my $session_code = KeyFilter::Replayer->new(file => "$dir/session.rec", output => $session_output, fast => 1)->run ;

my $took = Time::HiRes::time() - $began ;

close $session_output ;

is(read_file("$dir/session.out"), $original->{output}, 'the fast replay of a real session shows what the session showed') ;
is($session_code, 5, 'with its exit code') ;
cmp_ok($took, '<', 0.25, 'without its pauses') ;

# the command line

is_deeply(KeyFilter::CLI::parse_arguments('--replay', 'f', '--fast'), { command => [], replay => 'f', fast => 1 }, '--fast after --replay') ;
is_deeply(KeyFilter::CLI::parse_arguments('--fast', '--replay', 'f'), { command => [], replay => 'f', fast => 1 }, 'or before') ;

for my $case ([['--fast'], qr/\A--fast can only be used with --replay/], [['--fast', '--', 'true'], qr/--fast can only be used with --replay/], [['--fast', '--record', 'f'], qr/--fast can only be used with --replay/], [['--replay', 'f', '--fast=1'], qr/\Aoption '--fast' takes no value/], [['--fast', '--discover'], qr/--discover cannot be used/])
	{
	my ($arguments, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::CLI::parse_arguments(@$arguments) ; }), $pattern, "refused: @$arguments") ;
	}

write_file("$dir/long.rec", $header, "0.000000 O start\\r\\n\n", "20.000000 O middle\\r\\n\n", "40.000000 O end\\r\\n\n", "40.500000 X 7\n") ;

$began = Time::HiRes::time() ;

my $shown = qx{$^X $script --replay $dir/long.rec --fast} ;

is($shown, "start\r\nmiddle\r\nend\r\n", 'keyfilter --replay --fast shows the output') ;
is($? >> 8, 7, 'and returns the exit code') ;
cmp_ok(Time::HiRes::time() - $began, '<', 5, 'of a recording that lasts forty seconds, in a moment') ;
is(qx{$^X $script --fast --replay=$dir/long.rec}, $shown, 'the order of the options does not matter') ;

like(qx{$^X $script --fast 2>&1}, qr/\Akeyfilter: --fast can only be used with --replay\n\z/, 'the command line refuses --fast alone') ;
is($? >> 8, 1, 'with a usage code') ;

done_testing ;
