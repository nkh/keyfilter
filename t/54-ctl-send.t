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

my $script  = "$FindBin::Bin/../keyfilter" ;
my $dir     = temp_dir() ;
my $sockets = "$dir/sockets" ;
my $counter = 0 ;

sub ctl
{
my (@arguments) = @_ ;

my $name = 'ctl' . ++$counter ;

open(my $out, '>', "$dir/$name.out") or die ;
open(my $err, '>', "$dir/$name.err") or die ;

my $code = KeyFilter::Ctl::run(argv => \@arguments, stdout => $out, stderr => $err, dir => $sockets) ;

close $out ;
close $err ;

return { code => $code, out => read_file("$dir/$name.out"), err => read_file("$dir/$name.err") } ;
}

# -----------------------------------------------------------------------------

sub received_by
{
my ($control) = @_ ;

my @commands ;
my $last = Time::HiRes::time() ;

while (Time::HiRes::time() - $last < 0.15)
	{
	for my $fh (IO::Select->new($control->handles)->can_read(0.05))
		{
		push @commands, $control->service($fh) ;
		
		$last = Time::HiRes::time() ;
		}
	}

return @commands ;
}

# -----------------------------------------------------------------------------

sub sleeper
{
my $pid = fork() ;

if ($pid == 0)
	{
	sleep 60 ;
	
	POSIX::_exit(0) ;
	}

return $pid ;
}

# -----------------------------------------------------------------------------

# an instance to talk to

my $alive   = sleeper() ;
my $control = KeyFilter::Control->new(dir => $sockets, pid => $alive, info => { command => 'bash' }) ;

my $sent = ctl('send', 'hello') ;

is($sent->{code}, 0, 'send succeeds') ;
is($sent->{out}, '', 'and prints nothing') ;
is($sent->{err}, '', 'nor a message') ;

my @commands = received_by($control) ;

is_deeply(\@commands, [{ cmd => 'send', text => 'hello' }], 'the instance receives a send command with the text') ;

my @cases =
	(
	[['hello', 'world'], 'hello world', 'the arguments are joined with a space'],
	[['abc<<Enter>>'], "abc\r", 'key symbols are resolved'],
	[['git status\n'], "git status\n", 'escapes are resolved'],
	[['<<C-c>>'], "\x03", 'a control key'],
	[['<<Up>><<Up>><<Enter>>'], "\e[A\e[A\r", 'several keys'],
	[['spaced  '], 'spaced  ', 'spaces at the end are kept'],
	[['  spaced'], 'spaced', 'spaces at the start are not, write \\x20'],
	[['\x20x'], ' x', 'a space can be written'],
	[["caf\xc3\xa9"], "caf\xc3\xa9", 'bytes outside ascii are kept'],
	[['a\#b'], 'a#b', 'a hash is written \#'],
	[['say "hi" and \'bye\''], 'say "hi" and \'bye\'', 'quotes are text'],
	[['$HOME `x` *'], '$HOME `x` *', 'characters of the shell are text'],
	[['\x00\xff'], "\x00\xff", 'any byte can be sent'],
	[['-n'], '-n', 'text that looks like an option is text'],
	[['--help'], '--help', 'even --help'],
	) ;

for my $case (@cases)
	{
	my ($arguments, $expected, $name) = @$case ;
	
	is(ctl('send', @$arguments)->{code}, 0, "send succeeds: $name") ;
	
	my ($command) = received_by($control) ;
	
	is($command->{text}, $expected, $name) ;
	}

is(ctl('send', 'one')->{code}, 0, 'several sends can follow') ;
is(ctl('send', 'two')->{code}, 0, 'one after the other') ;

@commands = received_by($control) ;

is_deeply([ map { $_->{text} } @commands ], ['one', 'two'], 'and arrive in order') ;

my $big = 'x' x 60000 ;

is(ctl('send', $big)->{code}, 0, 'a long text is sent') ;

@commands = received_by($control) ;

is(length $commands[0]{text}, 60000, 'completely') ;

# what is refused before anything is sent

for my $case (
	[['send'], qr/\Akeyfilterctl: send requires text\n\z/],
	[['send', ''], qr/\Akeyfilterctl: send requires text\n\z/],
	[['send', "line\nbreak"], qr/\Akeyfilterctl: the text cannot contain a line end, write \\n\n\z/],
	[['send', "line\rbreak"], qr/\Akeyfilterctl: the text cannot contain a line end/],
	[['send', 'bad<<nokey>>'], qr/\Akeyfilterctl: unknown key specification 'nokey'\n\z/],
	[['send', 'bad<<Enter'], qr/\Akeyfilterctl: unterminated key symbol/],
	[['send', 'bad\q'], qr/\Akeyfilterctl: unknown escape/],
	[['send', ('x' x 70000)], qr/\Akeyfilterctl: the command is too long\n\z/],
	[['send', '# only a comment'], qr/\Akeyfilterctl: send requires text\n\z/],
	)
	{
	my ($arguments, $pattern) = @$case ;
	
	my $failed = ctl(@$arguments) ;
	
	like($failed->{err}, $pattern, 'refused: ' . substr(join(' ', @$arguments), 0, 40) =~ s/[\r\n]/ /gr) ;
	is($failed->{code}, 1, 'with a usage code') ;
	is($failed->{out}, '', 'and no output') ;
	}

is_deeply([ received_by($control) ], [], 'nothing of what was refused reached the instance') ;

# choosing the instance

my $other_pid     = sleeper() ;
my $other_control = KeyFilter::Control->new(dir => $sockets, pid => $other_pid, info => { command => 'vim' }) ;

my $ambiguous = ctl('send', 'x') ;

is($ambiguous->{code}, 2, 'with several instances and no pid send fails') ;
is($ambiguous->{err}, "keyfilterctl: several keyfilter instances are running (pids " . join(', ', sort { $a <=> $b } $alive, $other_pid) . "), choose one with --pid\n", 'and lists them') ;
is_deeply([ received_by($control), received_by($other_control) ], [], 'nothing is sent to anybody') ;

is(ctl('--pid', $other_pid, 'send', 'to vim')->{code}, 0, '--pid chooses the instance') ;

is_deeply([ map { $_->{text} } received_by($other_control) ], ['to vim'], 'which gets the text') ;
is_deeply([ received_by($control) ], [], 'and the other does not') ;

is(ctl('-p', $alive, 'send', 'to bash')->{code}, 0, 'so does -p') ;
is_deeply([ map { $_->{text} } received_by($control) ], ['to bash'], 'and the first instance gets its text') ;
is(ctl("--pid=$alive", 'send', 'equal')->{code}, 0, 'and the form with an equal sign') ;
is_deeply([ map { $_->{text} } received_by($control) ], ['equal'], 'which works too') ;

my $nobody = ctl('--pid', '999999', 'send', 'x') ;

is($nobody->{code}, 2, 'a pid that is not an instance fails') ;
is($nobody->{err}, "keyfilterctl: no keyfilter instance has the pid 999999\n", 'and says so') ;

$other_control->close ;
kill 'KILL', $other_pid ;
waitpid($other_pid, 0) ;

is(ctl('send', 'alone')->{code}, 0, 'with one instance left no pid is needed') ;
is_deeply([ map { $_->{text} } received_by($control) ], ['alone'], 'it gets the text') ;

# no instance, an instance that is not there

$control->close ;
kill 'KILL', $alive ;
waitpid($alive, 0) ;

my $none = ctl('send', 'x') ;

is($none->{code}, 2, 'without an instance send fails') ;
is($none->{err}, "keyfilterctl: no keyfilter instance is running\n", 'and says so') ;
is($none->{out}, '', 'with no output') ;

my $dead_pid = fork() ;

POSIX::_exit(0) if $dead_pid == 0 ;

waitpid($dead_pid, 0) ;

my $stale = KeyFilter::Control->new(dir => $sockets, pid => $dead_pid) ;

is(ctl('send', 'x')->{err}, "keyfilterctl: no keyfilter instance is running\n", 'the socket of a process that is gone is not an instance') ;

$stale->close ;

my $crashed_pid = sleeper() ;
my $crash       = fork() ;

if ($crash == 0)
	{
	KeyFilter::Control->new(dir => $sockets, pid => $crashed_pid) ;
	
	POSIX::_exit(0) ;
	}

waitpid($crash, 0) ;

my $refused = ctl('send', 'x') ;

is($refused->{code}, 2, 'a process that is alive but whose socket nobody listens to fails') ;
like($refused->{err}, qr/\Akeyfilterctl: cannot connect to the instance \Q$crashed_pid\E: Connection refused\n\z/, 'and says why') ;

kill 'KILL', $crashed_pid ;
waitpid($crashed_pid, 0) ;

# a running keyfilter

sub start_instance
{
my ($home, @command) = @_ ;

pipe(my $read, my $write) or die ;
pipe(my $stdin_read, my $stdin_write) or die ;

my $pid = fork() ;

if ($pid == 0)
	{
	close $read ;
	close $stdin_write ;
	
	$ENV{HOME} = "$home" ;
	
	open(STDIN, '<&', $stdin_read) ;
	open(STDOUT, '>&', $write) ;
	open(STDERR, '>', '/dev/null') ;
	
	exec $^X, $script, '--', @command ;
	}

close $write ;

my $deadline = Time::HiRes::time() + 10 ;

Time::HiRes::sleep(0.05) until (-d "$home/.config/keyfilter/sockets" && glob("$home/.config/keyfilter/sockets/*.sock")) || Time::HiRes::time() > $deadline ;

close $stdin_read ;

return { pid => $pid, out => $read, in => $stdin_write } ;
}

# -----------------------------------------------------------------------------

symlink($script, "$dir/keyfilterctl") or die "symlink: $!" ;

my $home     = temp_dir() ;
my $instance = start_instance($home, 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 5') ;

like(read_until($instance->{out}, qr/ready\n/, 10), qr/ready/, 'a keyfilter runs') ;

my $result = qx{HOME=$home $dir/keyfilterctl send hello 2>&1} ;

is($result, '', 'keyfilterctl send writes nothing') ;
is($? >> 8, 0, 'and succeeds') ;
is(read_all($instance->{out}), 'hello', 'and the command of the instance receives the text') ;

waitpid($instance->{pid}, 0) ;

my $shell_home = temp_dir() ;
my $shell      = start_instance($shell_home, 'sh', '-c', 'read a ; read b ; echo got:$a:$b') ;

system("HOME=$shell_home $dir/keyfilterctl send 'one<<Enter>>two<<Enter>>'") ;

like(read_all($shell->{out}), qr/got:one:two\r\n/, 'keys sent with keyfilterctl are lines for a shell') ;

waitpid($shell->{pid}, 0) ;

my $first_home  = temp_dir() ;
my $second_home = $first_home ;
my $a_instance  = start_instance($first_home, 'sh', '-c', 'stty raw -echo ; echo a-ready ; head -c 1') ;

like(read_until($a_instance->{out}, qr/a-ready\n/, 10), qr/a-ready/, 'a first instance runs') ;

my $b_instance = start_instance($first_home, 'sh', '-c', 'stty raw -echo ; echo b-ready ; head -c 1') ;

like(read_until($b_instance->{out}, qr/b-ready\n/, 10), qr/b-ready/, 'and a second one') ;

my $two = qx{HOME=$first_home $dir/keyfilterctl send x 2>&1} ;

is($? >> 8, 2, 'with two instances send needs a pid') ;
like($two, qr/several keyfilter instances are running \(pids $a_instance->{pid}, $b_instance->{pid}\), choose one with --pid/, 'and says which') ;

system("HOME=$first_home $dir/keyfilterctl --pid $b_instance->{pid} send y") ;

is(read_all($b_instance->{out}), 'y', 'the instance that was chosen gets the text') ;

system("HOME=$first_home $dir/keyfilterctl send z") ;

is(read_all($a_instance->{out}), 'z', 'and now that the other one is gone, the first one gets it') ;

waitpid($_->{pid}, 0) for $a_instance, $b_instance ;

done_testing ;
