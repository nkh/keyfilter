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

my $dir     = temp_dir() ;
my $counter = 0 ;

# a child that puts its terminal in raw mode, says it is ready and collects what it receives

sub collector
{
my (%options) = @_ ;

my $name   = 'case' . ++$counter ;
my $reader = $options{reader} // "head -c $options{bytes}" ;
my $stty   = $options{stty} // 'raw -echo' ;

my ($input, $writer) = pipe_pair() ;

my $pty = start_engine({ input => $input, filter => $options{filter} }, 'sh', '-c', "stty $stty ; echo ready > $dir/$name.ready ; $reader > $dir/$name.out") ;

die "the child is not ready\n" unless wait_for_file("$dir/$name.ready") ;

return { pty => $pty, writer => $writer, input => $input, out => "$dir/$name.out" } ;
}

# -----------------------------------------------------------------------------

# write the data into the input pipe while the engine moves it along

sub feed
{
my ($case, $data) = @_ ;

$case->{writer}->blocking(0) ;

my $deadline = Time::HiRes::time() + 30 ;

while (length $data && Time::HiRes::time() < $deadline)
	{
	my $written = syswrite($case->{writer}, $data) ;
	
	substr($data, 0, $written, '') if defined $written ;
	
	$case->{pty}->pump(0.02) ;
	}

$case->{writer}->blocking(1) ;

return length $data == 0 ;
}

# -----------------------------------------------------------------------------

sub settle
{
my ($case, $timeout) = @_ ;

my $pty      = $case->{pty} ;
my $deadline = Time::HiRes::time() + ($timeout // 30) ;

while (Time::HiRes::time() < $deadline)
	{
	my $waiting = IO::Select->new($case->{input})->can_read(0) ;
	
	return 1 if !$waiting && !$pty->pending_input ;
	
	$pty->pump(0.02) ;
	}

return 0 ;
}

# -----------------------------------------------------------------------------

sub received
{
my ($case) = @_ ;

$case->{pty}->wait_exit ;

return read_file($case->{out}) ;
}

# -----------------------------------------------------------------------------

# exact forwarding

my $case = collector(bytes => 5) ;

syswrite($case->{writer}, 'hello') ;

is($case->{pty}->forward_input, 5, 'forward_input returns the number of bytes read') ;
is($case->{pty}->pending_input, 0, 'and everything is written to the child') ;
is(received($case), 'hello', 'the child receives the bytes') ;

$case = collector(bytes => 256) ;

syswrite($case->{writer}, join('', map { chr } 0 .. 255)) ;

$case->{pty}->forward_input ;

is(received($case), join('', map { chr } 0 .. 255), 'all byte values are forwarded unchanged, in order') ;

$case = collector(bytes => 12) ;

for my $chunk ('abc', 'defg', 'hi', "jkl") 
	{
	syswrite($case->{writer}, $chunk) ;
	
	is($case->{pty}->forward_input, length $chunk, "chunk '$chunk' is forwarded") ;
	}

is(received($case), 'abcdefghijkl', 'chunks arrive in order') ;

$case = collector(bytes => 3) ;

syswrite($case->{writer}, "\xc3\xa9!") ;

$case->{pty}->forward_input ;

is(received($case), "\xc3\xa9!", 'UTF-8 bytes are not changed') ;

$case = collector(bytes => 20000) ;

my $block = join('', map { chr(65 + $_ % 26) } 0 .. 19999) ;

syswrite($case->{writer}, $block) ;

my @counts ;
my $total = 0 ;

while ($total < 20000)
	{
	my $count = $case->{pty}->forward_input ;
	
	push @counts, $count ;
	
	$total += $count ;
	}

is_deeply(\@counts, [8192, 8192, 3616], 'input is read in blocks of at most 8192 bytes') ;
ok(settle($case), 'the pending bytes are flushed') ;
is(received($case), $block, 'and all of it arrives') ;

# large input and a child that is slow to read

$case = collector(bytes => 300000, stty => 'raw -echo', reader => 'sleep 1 ; head -c 300000') ;

srand(42) ;

my $big = join('', map { chr int rand 256 } 1 .. 300000) ;

ok(feed($case, $big), 'a large input is written into the pipe') ;
ok(settle($case), 'and the engine moves all of it, whatever the child does') ;
is(received($case), $big, 'a large binary input arrives complete and in order') ;

# backpressure keeps the rest pending

$case = collector(bytes => 100000, reader => 'sleep 2 ; head -c 100000') ;

syswrite($case->{writer}, 'x' x 60000) ;

my $read = 0 ;

$read += $case->{pty}->forward_input for 1 .. 8 ;

is($read, 60000, 'the engine reads what it is given') ;
cmp_ok($case->{pty}->pending_input, '>', 0, 'what the child cannot take yet stays pending') ;

my $pending   = $case->{pty}->pending_input ;
my $remaining = $case->{pty}->flush_input ;

cmp_ok($remaining, '<=', $pending, 'flushing never adds to what is pending') ;
is($case->{pty}->pending_input, $remaining, 'flush_input returns what is still pending') ;

syswrite($case->{writer}, 'y' x 40000) ;

ok(feed($case, ''), 'nothing more to feed') ;

my $deadline = Time::HiRes::time() + 20 ;

while ($case->{pty}->pending_input && Time::HiRes::time() < $deadline)
	{
	$case->{pty}->pump(0.05) ;
	}

$case->{pty}->forward_input while IO::Select->new($case->{input})->can_read(0) && Time::HiRes::time() < $deadline ;

until (!$case->{pty}->pending_input || Time::HiRes::time() > $deadline)
	{
	$case->{pty}->pump(0.05) ;
	}

is($case->{pty}->pending_input, 0, 'the pending bytes are delivered when the child reads') ;
is(received($case), ('x' x 60000) . ('y' x 40000), 'in the original order') ;

# filter

my @seen ;

$case = collector(bytes => 5, filter => sub { push @seen, $_[0] ; return uc $_[0] ; }) ;

syswrite($case->{writer}, 'hello') ;

$case->{pty}->forward_input ;

is(received($case), 'HELLO', 'the filter changes what the child receives') ;
is_deeply(\@seen, ['hello'], 'the filter is called with the bytes that were read') ;

$case = collector(bytes => 4, filter => sub { return $_[0] =~ s/(.)/$1$1/gr ; }) ;

syswrite($case->{writer}, 'ab') ;

$case->{pty}->forward_input ;

is(received($case), 'aabb', 'a filter can add bytes') ;

$case = collector(bytes => 3, reader => 'timeout --foreground 1 cat', filter => sub { return '' ; }) ;

syswrite($case->{writer}, 'secret') ;

is($case->{pty}->forward_input, 6, 'a filter that blocks everything still consumes the input') ;
is($case->{pty}->pending_input, 0, 'and nothing is pending') ;
is(received($case), '', 'the child receives nothing') ;

$case = collector(bytes => 3, filter => sub { return undef ; }) ;

syswrite($case->{writer}, 'abc') ;

$case->{pty}->forward_input ;

is($case->{pty}->pending_input, 0, 'a filter returning undef is the same as returning nothing') ;

$case->{pty}->send_input('xyz') ;

is(received($case), 'xyz', 'send_input bypasses the filter') ;

my $chunks = 0 ;

$case = collector(bytes => 6, filter => sub { $chunks++ ; return $_[0] ; }) ;

syswrite($case->{writer}, 'abc') ;
$case->{pty}->forward_input ;
syswrite($case->{writer}, 'def') ;
$case->{pty}->forward_input ;

received($case) ;

is($chunks, 2, 'the filter is called once for each read') ;

$case = collector(bytes => 1, filter => sub { die "boom\n" ; }) ;

syswrite($case->{writer}, 'a') ;

like(failure_of(sub { $case->{pty}->forward_input ; }), qr/\Aboom/, 'an error in the filter is not hidden') ;
is($case->{pty}->pending_input, 0, 'and nothing was sent') ;

$case->{pty}->signal('KILL') ;

# send_input, flush_input, ordering

$case = collector(bytes => 9) ;

$case->{pty}->send_input('abc') ;

syswrite($case->{writer}, 'def') ;

$case->{pty}->forward_input ;
$case->{pty}->send_input('ghi') ;

is(received($case), 'abcdefghi', 'injected input and forwarded input keep their order') ;

my $unspawned = KeyFilter::PTY->new(command => ['true']) ;

is($unspawned->send_input('abc'), 3, 'without a child the input stays pending') ;
is($unspawned->flush_input, 3, 'and flushing does nothing') ;
is($unspawned->pending_input, 3, 'it is still there') ;
is($unspawned->send_input(''), 3, 'sending nothing changes nothing') ;

my $gone = start_pty('true') ;

read_all($gone) ;
$gone->wait_exit ;

is($gone->send_input('abc'), 0, 'input for a child that is gone is dropped, without an error') ;
is($gone->pending_input, 0, 'and it is not kept') ;

# end of input

my ($closed_input, $closed_writer) = pipe_pair() ;

close $closed_writer ;

my $ending = start_engine({ input => $closed_input }, 'sh', '-c', "stty raw -echo eof '^E' ; echo ready > $dir/eof.ready ; timeout --foreground 1 cat > $dir/eof.out") ;

wait_for_file("$dir/eof.ready") ;

is($ending->input_eof, 0, 'input is not at its end at the start') ;
is($ending->forward_input, 0, 'forward_input returns 0 at the end of the input') ;
is($ending->input_eof, 1, 'and the end is remembered') ;
is($ending->forward_input, 0, 'reading again gives 0 again') ;
$ending->wait_exit ;
is(read_file("$dir/eof.out"), "\x05", 'the end of the input is sent once, as the end-of-file character of the terminal') ;

$case = collector(reader => 'timeout --foreground 1 cat', stty => 'raw -echo') ;

syswrite($case->{writer}, 'ab') ;

close $case->{writer} ;

$case->{pty}->forward_input ;
$case->{pty}->forward_input ;
$case->{pty}->forward_input ;

is(received($case), "ab\x04", 'the default end-of-file character is sent once to a terminal in raw mode') ;

my ($cat_input, $cat_writer) = pipe_pair() ;

my $cat = start_engine({ input => $cat_input }, 'sh', '-c', "cat > $dir/cat.out") ;

syswrite($cat_writer, "line one\nline two\n") ;

close $cat_writer ;

my $deadline_cat = Time::HiRes::time() + 10 ;

while ($cat->is_running && Time::HiRes::time() < $deadline_cat)
	{
	$cat->pump(0.05) ;
	}

is($cat->exit_code, 0, 'a cooked terminal reader ends when the input ends') ;
is(read_file("$dir/cat.out"), "line one\nline two\n", 'after receiving all the lines') ;

my ($partial_input, $partial_writer) = pipe_pair() ;

my $partial = start_engine({ input => $partial_input }, 'sh', '-c', "cat > $dir/partial.out") ;

syswrite($partial_writer, 'no newline') ;

close $partial_writer ;

$deadline_cat = Time::HiRes::time() + 10 ;

while ($partial->is_running && Time::HiRes::time() < $deadline_cat)
	{
	$partial->pump(0.05) ;
	}

is($partial->exit_code, 0, 'a last line without a newline does not keep the child waiting') ;
is(read_file("$dir/partial.out"), 'no newline', 'and the line is delivered') ;

my ($empty_input, $empty_writer) = pipe_pair() ;

my $empty = start_engine({ input => $empty_input }, 'sh', '-c', "cat > $dir/empty.out") ;

close $empty_writer ;

$deadline_cat = Time::HiRes::time() + 10 ;

while ($empty->is_running && Time::HiRes::time() < $deadline_cat)
	{
	$empty->pump(0.05) ;
	}

is($empty->exit_code, 0, 'an empty input ends the child') ;
is(read_file("$dir/empty.out"), '', 'which received nothing') ;

# non blocking input

my ($nb_input, $nb_writer) = pipe_pair() ;

$nb_input->blocking(0) ;

my $nonblocking = start_engine({ input => $nb_input }, 'sleep', '5') ;

is($nonblocking->forward_input, undef, 'no data on a non blocking input is not an error') ;
is($nonblocking->input_eof, 0, 'and not an end') ;

$nonblocking->signal('KILL') ;

# pump

my ($pump_input, $pump_writer) = pipe_pair() ;

my $pumped = start_engine({ input => $pump_input }, 'sleep', '5') ;

my $start = Time::HiRes::time() ;

is($pumped->pump(0.3), 0, 'pump returns 0 when nothing happens') ;
cmp_ok(Time::HiRes::time() - $start, '>=', 0.25, 'after waiting for the timeout') ;

$start = Time::HiRes::time() ;

is($pumped->pump(0), 0, 'pump with no timeout does not wait') ;
cmp_ok(Time::HiRes::time() - $start, '<', 0.2, 'and returns at once') ;

syswrite($pump_writer, 'abc') ;

$start = Time::HiRes::time() ;

cmp_ok($pumped->pump(5), '>=', 1, 'pump counts the input that is available') ;
cmp_ok(Time::HiRes::time() - $start, '<', 2, 'without waiting for the timeout') ;

close $pump_writer ;

my $limit = Time::HiRes::time() + 10 ;

$pumped->pump(1) until $pumped->input_eof || Time::HiRes::time() > $limit ;

is($pumped->input_eof, 1, 'pump handles the end of the input and records it') ;

1 while $pumped->pump(0.2) ;

$start = Time::HiRes::time() ;

$pumped->pump(0.3) ;

cmp_ok(Time::HiRes::time() - $start, '>=', 0.25, 'after the end of the input pump waits instead of spinning') ;

$pumped->signal('KILL') ;

# defaults

is(KeyFilter::PTY->new(command => ['true'])->input, \*STDIN, 'the input is the standard input by default') ;
is(KeyFilter::PTY->new(command => ['true'], input => $pump_input)->input, $pump_input, 'and can be chosen') ;

# raw mode on a terminal

my ($terminal, $slave) = new_terminal() ;

my $before = termios_of($slave) ;

ok($before->{lflag} & POSIX::ICANON(), 'a new terminal is canonical') ;
ok($before->{lflag} & POSIX::ECHO(), 'with echo') ;

my $engine = KeyFilter::PTY->new(command => ['true'], input => $slave) ;

ok($engine->raw_mode, 'raw mode is entered on a terminal') ;

my $raw = termios_of($slave) ;

for my $flag (qw(ICANON ECHO ECHONL ISIG IEXTEN))
	{
	ok(!($raw->{lflag} & POSIX->can($flag)->()), "$flag is off in raw mode") ;
	}

for my $flag (qw(ICRNL INLCR IGNCR IXON ISTRIP BRKINT IGNBRK PARMRK))
	{
	ok(!($raw->{iflag} & POSIX->can($flag)->()), "$flag is off in raw mode") ;
	}

ok(!($raw->{oflag} & POSIX::OPOST()), 'output processing is off in raw mode') ;
ok(($raw->{cflag} & POSIX::CSIZE()) == POSIX::CS8(), 'characters have 8 bits') ;
ok(!($raw->{cflag} & POSIX::PARENB()), 'without parity') ;
is($raw->{vmin}, 1, 'a read waits for one byte') ;
is($raw->{vtime}, 0, 'without a timeout') ;

ok($engine->raw_mode, 'entering raw mode twice is fine') ;

$engine->restore_mode ;

my $after = termios_of($slave) ;

is_deeply($after, $before, 'restoring gives back every setting') ;

$engine->restore_mode ;

is_deeply(termios_of($slave), $before, 'restoring twice changes nothing') ;

ok($engine->raw_mode, 'raw mode can be entered again') ;

$engine->raw_mode ;
$engine->restore_mode ;

is_deeply(termios_of($slave), $before, 'one restore undoes entering twice, the original is not lost') ;

# the original settings are kept, whatever they are

my $custom = POSIX::Termios->new() ;

$custom->getattr(fileno $slave) ;
$custom->setcc(POSIX::VEOF(), 5) ;
$custom->setcc(POSIX::VMIN(), 3) ;
$custom->setcc(POSIX::VTIME(), 7) ;
$custom->setattr(fileno $slave, POSIX::TCSANOW()) ;

my $custom_before = termios_of($slave) ;

$engine->raw_mode ;
$engine->restore_mode ;

is_deeply(termios_of($slave), $custom_before, 'unusual settings come back too') ;

# typing is immediate in raw mode

syswrite($terminal, 'abc') ;

ok(!IO::Select->new($slave)->can_read(0.3), 'in cooked mode a partial line is not readable') ;
like(read_until($terminal, qr/abc/, 2), qr/abc/, 'and it is echoed') ;

$engine->raw_mode ;

syswrite($terminal, 'def') ;

ok(IO::Select->new($slave)->can_read(2), 'in raw mode typed bytes are readable at once') ;

my $typed = '' ;

until ($typed =~ /def\z/ || !IO::Select->new($slave)->can_read(2))
	{
	sysread($slave, my $chunk, 100) ;
	
	$typed .= $chunk ;
	}

like($typed, qr/def\z/, 'and are what was typed') ;
is(read_until($terminal, qr/./, 0.4), '', 'and are not echoed') ;

$engine->restore_mode ;

# a terminal is restored even if nobody asks

$engine->raw_mode ;

KeyFilter::PTY::restore_all() ;

is_deeply(termios_of($slave), $custom_before, 'restore_all restores every terminal in raw mode') ;

$engine->raw_mode ;

my $forked = fork() ;

if ($forked == 0)
	{
	exit 0 ;
	}

waitpid($forked, 0) ;

ok(!(termios_of($slave)->{lflag} & POSIX::ICANON()), 'a forked process that exits does not restore the terminal of its parent') ;

$engine->restore_mode ;

# input that is not a terminal

my ($plain_input, $plain_writer) = pipe_pair() ;

my $plain = KeyFilter::PTY->new(command => ['true'], input => $plain_input) ;

is($plain->raw_mode, 0, 'a pipe has no raw mode') ;
is($plain->restore_mode, $plain, 'and restoring is harmless') ;

open(my $file, '<', "$0") or die ;

is(KeyFilter::PTY->new(command => ['true'], input => $file)->raw_mode, 0, 'a regular file has no raw mode') ;

close $file ;

is(KeyFilter::PTY::enter_raw_mode($file), undef, 'a closed handle has no raw mode') ;
is(KeyFilter::PTY::leave_raw_mode(undef), undef, 'leaving a mode that was not entered does nothing') ;

done_testing ;
