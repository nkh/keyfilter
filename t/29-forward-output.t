#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use IO::Select () ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

# forward_output, one read at a time

my $path = "$dir/out1" ;

open(my $out, '>', $path) or die ;

my $pty = start_engine({ output => $out }, 'sh', '-c', 'echo hello ; sleep 0.2') ;

my $deadline = Time::HiRes::time() + 5 ;
my $count ;

until (defined $count && $count > 0 || Time::HiRes::time() > $deadline)
	{
	IO::Select->new($pty->master)->can_read(0.1) ;
	
	$count = $pty->forward_output ;
	}

is($count, 7, 'forward_output returns the number of bytes read') ;
is(read_file($path), "hello\r\n", 'and writes them to the output') ;
is($pty->output_closed, 0, 'the output is not closed while the child lives') ;
is($pty->forward_output, undef, 'no data is not an error') ;

$pty->wait_exit ;

$deadline = Time::HiRes::time() + 5 ;

until ($pty->output_closed || Time::HiRes::time() > $deadline)
	{
	IO::Select->new($pty->master)->can_read(0.1) ;
	
	$pty->forward_output ;
	}

is($pty->output_closed, 1, 'the end of the child output is detected') ;
is($pty->forward_output, 0, 'and reported as 0') ;
is($pty->finished, 1, 'the engine is finished when the output is closed') ;

# exact bytes

my $all = run_engine({}, 'sh', '-c', 'stty raw -echo ; "$0" -e "print map { chr } 0 .. 255"', $^X) ;

is($all->{code}, 0, 'the command exits normally') ;
is($all->{output}, join('', map { chr } 0 .. 255), 'all byte values come out unchanged') ;

my $cooked = run_engine({}, 'sh', '-c', 'printf "a\nb\n"') ;

is($cooked->{output}, "a\r\nb\r\n", 'the terminal of the child turns a newline into carriage return and newline') ;

my $large = run_engine({}, 'sh', '-c', 'stty raw -echo ; "$0" -e "print q(0123456789) x 100000"', $^X) ;

is(length $large->{output}, 1000000, 'a large output arrives complete') ;
is($large->{output}, '0123456789' x 100000, 'and unchanged') ;

my $numbered = run_engine({}, 'sh', '-c', 'stty raw -echo ; "$0" -e "print qq(\$_\n) for 1 .. 50000"', $^X) ;

is($numbered->{output}, join('', map { "$_\n" } 1 .. 50000), 'the order of the output is kept') ;

my $both = run_engine({}, 'sh', '-c', 'echo out ; echo err >&2 ; echo out2') ;

is($both->{output}, "out\r\nerr\r\nout2\r\n", 'standard output and standard error are both forwarded, in order') ;

my $silent = run_engine({}, 'true') ;

is($silent->{output}, '', 'a silent command gives no output') ;
is($silent->{code}, 0, 'and its exit code') ;

# exit codes

for my $code (0, 1, 5, 42, 255)
	{
	is(run_engine({}, 'sh', '-c', "exit $code")->{code}, $code, "run returns exit code $code") ;
	}

is(run_engine({}, 'sh', '-c', 'kill -9 $$')->{code}, 137, 'run returns 128 plus the signal for a killed command') ;
is(run_engine({}, 'sh', '-c', 'echo before ; kill -15 $$')->{output}, "before\r\n", 'output written before the end is not lost') ;

for (1 .. 30)
	{
	my $quick = run_engine({}, 'sh', '-c', 'echo fast ; exit 3') ;
	
	last unless $quick->{output} eq "fast\r\n" && $quick->{code} == 3 ;
	
	$quick = undef ;
	}

pass('thirty quick commands lose nothing') ;

my $fast = 0 ;

$fast += run_engine({}, 'echo', 'x')->{output} eq "x\r\n" for 1 .. 30 ;

is($fast, 30, 'a command that ends at once still has all its output forwarded') ;

# input and output together

my $cat = run_engine({ input_data => "hello\n" }, 'cat') ;

is($cat->{code}, 0, 'cat ends when the input ends') ;
is($cat->{output}, "hello\r\nhello\r\n", 'the terminal echoes the line and cat writes it back') ;

srand(7) ;

my $big = join('', map { chr int rand 256 } 1 .. 300000) ;

my $exchange = engine_process({}, 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 300000') ;

$exchange->read_until(qr/ready\n/) ;

my $returned = '' ;
my $to_send  = $big ;

$exchange->{input}->blocking(0) ;

my $limit = Time::HiRes::time() + 60 ;

while ((length $to_send || length $returned < 300000) && Time::HiRes::time() < $limit)
	{
	if (length $to_send)
		{
		my $written = syswrite($exchange->{input}, $to_send) ;
		
		substr($to_send, 0, $written, '') if defined $written ;
		}
	
	if (IO::Select->new($exchange->{output})->can_read(0.01))
		{
		sysread($exchange->{output}, my $chunk, 65536) ;
		
		$returned .= $chunk if defined $chunk ;
		}
	}

is(length $returned, 300000, 'a large exchange brings back the same amount of data') ;
ok($returned eq $big, 'and the same data, input and output flow at the same time') ;
is($exchange->finish, 0, 'the engine ends') ;

# on_output

my @chunks ;

my $observed = run_engine({ on_output => sub { push @chunks, $_[0] ; } }, 'sh', '-c', 'echo one ; sleep 0.2 ; echo two') ;

is(join('', @chunks), $observed->{output}, 'on_output sees everything that is forwarded') ;
cmp_ok(scalar @chunks, '>=', 2, 'in the chunks it was read') ;
is((grep { !length } @chunks), 0, 'and never an empty chunk') ;

# a reader that is gone

pipe(my $gone_read, my $gone_write) or die ;

close $gone_read ;

my @seen_after ;

my $broken = KeyFilter::PTY->new(command => ['sh', '-c', 'echo before ; sleep 0.3 ; echo after ; exit 4'], output => $gone_write, on_output => sub { push @seen_after, $_[0] ; }) ;

is($broken->run, 4, 'run completes even if nobody reads the output') ;
is($broken->output_broken, 1, 'the broken output is noticed') ;
is(join('', @seen_after), "before\r\nafter\r\n", 'on_output still sees the output') ;

# run

my $twice = KeyFilter::PTY->new(command => ['true'], output => do { open(my $null, '>', '/dev/null') ; $null }) ;

$twice->run ;

like(failure_of(sub { $twice->run ; }), qr/already been run/, 'a command is run once') ;

like(failure_of(sub { KeyFilter::PTY->new(command => ['no-such-command-xyz'])->run ; }), qr/cannot execute 'no-such-command-xyz'/, 'run reports a command that cannot be executed') ;

SKIP:
	{
	skip 'no /proc', 2 unless -d '/proc/self/fd' ;
	
	my $count = sub { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; } ;
	
	run_engine({}, 'true') ;
	
	my $before = $count->() ;
	
	run_engine({}, 'echo', 'x') for 1 .. 15 ;
	
	is($count->(), $before, 'running commands leaves no file descriptor open') ;
	
	my $reaped = KeyFilter::PTY->new(command => ['true'], output => do { open(my $null, '>', '/dev/null') ; $null }) ;
	
	$reaped->run ;
	
	is(waitpid($reaped->pid, POSIX::WNOHANG()), -1, 'the child is reaped when run returns') ;
	}

# a conversation with a process of its own

my $engine = engine_process({}, 'sh', '-c', 'echo ready ; read x ; echo got:$x ; read y ; echo and:$y') ;

like($engine->read_until(qr/ready\r\n/), qr/ready/, 'the prompt of the child is forwarded') ;

$engine->send("abc\n") ;

like($engine->read_until(qr/got:abc\r\n/), qr/got:abc/, 'what is typed reaches the child and its answer comes back') ;

$engine->send("def\n") ;

like($engine->read_until(qr/and:def\r\n/), qr/and:def/, 'a second exchange works') ;
is($engine->finish, 0, 'the engine ends with the exit code of the child') ;

my $quiet = engine_process({}, 'sh', '-c', 'read x ; echo "[$x]" ; exit 6') ;

$quiet->send("typed\n") ;

like($quiet->read_all, qr/\[typed\]/, 'a prompt-less child gets its input') ;
is($quiet->finish, 6, 'and its exit code is returned') ;

my $slow = engine_process({ output_nonblocking => 1 }, 'sh', '-c', 'stty raw -echo ; "$0" -e "print q(0123456789) x 30000"', $^X) ;

Time::HiRes::sleep(1) ;

is(length $slow->read_all(20), 300000, 'a non blocking output that is slow to be read loses nothing') ;
is($slow->finish, 0, 'and the engine ends normally') ;

# the terminal of the user

my ($terminal, $slave) = new_terminal() ;

my $before = termios_of($slave) ;
my $tty    = engine_process({ tty_input => $slave }, 'sh', '-c', 'echo ready ; read x ; echo got:$x') ;

like(read_until($tty->{output}, qr/ready\r\n/), qr/ready/, 'the child runs with the terminal of the user as input') ;

ok(!(termios_of($slave)->{lflag} & POSIX::ICANON()), 'the terminal of the user is in raw mode while the engine runs') ;

syswrite($terminal, "typed\r") ;

like($tty->read_all, qr/got:typed/, 'a carriage return typed in raw mode reaches the child as a line') ;
is($tty->finish, 0, 'the engine ends') ;
is_deeply(termios_of($slave), $before, 'the terminal of the user is restored') ;

# the command line

my $script = "$FindBin::Bin/../keyfilter" ;

is(qx{$^X $script -- sh -c 'echo hi ; exit 3' </dev/null}, "hi\r\n", 'keyfilter runs a command and shows its output') ;
is($? >> 8, 3, 'and exits with its exit code') ;

is(qx{$^X $script sh -c 'echo no-dashes' </dev/null}, "no-dashes\r\n", 'the double dash is optional') ;
is(qx{printf 'abc\\n' | $^X $script -- cat}, "abc\r\nabc\r\n", 'input of keyfilter reaches the command') ;
is(qx{$^X $script -- $^X -e 'print join("|", \@ARGV)' 'a b' c </dev/null}, 'a b|c', 'arguments are kept') ;

my $error = qx{$^X $script -- no-such-command-xyz 2>&1 </dev/null} ;

like($error, qr/\Akeyfilter: cannot execute 'no-such-command-xyz': No such file or directory\n\z/, 'a command that does not exist gives a clear message') ;
is($? >> 8, 255, 'and a failure code') ;

my $usage = qx{$^X $script 2>&1 </dev/null} ;

like($usage, qr/\AUsage: keyfilter/, 'no command gives the usage') ;
isnt($? >> 8, 0, 'and a failure code') ;

done_testing ;
