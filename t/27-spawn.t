#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use Cwd () ;
use POSIX () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub output_of
{
my (@command) = @_ ;

my $pty    = start_pty(@command) ;
my $output = read_all($pty) ;

$pty->wait_exit ;

return $output ;
}

# -----------------------------------------------------------------------------

# construction

like(failure_of(sub { KeyFilter::PTY->new() ; }), qr/no command to run/, 'a command is required') ;
like(failure_of(sub { KeyFilter::PTY->new(command => []) ; }), qr/no command to run/, 'an empty command is refused') ;
like(failure_of(sub { KeyFilter::PTY->new(command => 'sh') ; }), qr/no command to run/, 'the command must be a list') ;
like(failure_of(sub { KeyFilter::PTY->new(command => ['']) ; }), qr/no command to run/, 'an empty program name is refused') ;
like(failure_of(sub { KeyFilter::PTY->new(command => [undef]) ; }), qr/no command to run/, 'an undefined program name is refused') ;

my @command = ('sh', '-c', 'echo copied') ;
my $fresh   = KeyFilter::PTY->new(command => \@command) ;

isa_ok($fresh, 'KeyFilter::PTY') ;
ok(!defined $fresh->pid, 'a new object has no child') ;
ok(!defined $fresh->master, 'a new object has no pty') ;
ok(!defined $fresh->exit_code, 'a new object has no exit code') ;
is($fresh->is_running, 0, 'a new object is not running') ;

$command[2] = 'echo changed' ;
$fresh->spawn ;

like(read_all($fresh), qr/\Acopied\r\n\z/, 'the command is copied when the object is created') ;

$fresh->wait_exit ;

# running a command

my $pty = start_pty('sh', '-c', 'echo hello') ;

ok($pty->pid > 0, 'spawn gives a child pid') ;
isnt($pty->pid, $$, 'the child is another process') ;
ok(defined $pty->master, 'the pty master is available') ;
isa_ok($pty->master, 'IO::Pty') ;
ok(!$pty->master->blocking, 'the master is not blocking') ;
is(read_all($pty), "hello\r\n", 'the output of the child is read from the master') ;
is($pty->wait_exit, 0, 'the child exits with 0') ;
is($pty->exit_code, 0, 'the exit code is kept') ;
is($pty->wait_exit, 0, 'waiting twice gives the same code') ;
is($pty->is_running, 0, 'a finished child is not running') ;
is(waitpid($pty->pid, POSIX::WNOHANG()), -1, 'the child was reaped, it is not a zombie') ;

like(failure_of(sub { $pty->spawn ; }), qr/child already spawned/, 'spawn twice is refused') ;

is(output_of('echo', 'two words', 'x'), "two words x\r\n", 'a program found in the path runs with its arguments') ;
is(output_of($^X, '-e', 'print "perl\n"'), "perl\r\n", 'a program given with its full path runs') ;

# exit codes

for my $code (0, 1, 2, 7, 42, 127, 255)
	{
	my $child = start_pty('sh', '-c', "exit $code") ;
	
	read_all($child) ;
	
	is($child->wait_exit, $code, "exit code $code") ;
	}

my %signals = (KILL => 9, TERM => 15, INT => 2, HUP => 1, QUIT => 3) ;

for my $name (sort keys %signals)
	{
	my $child = start_pty('sh', '-c', "kill -$name \$\$") ;
	
	read_all($child) ;
	
	is($child->wait_exit, 128 + $signals{$name}, "killed by $name gives 128 plus the signal number") ;
	}

# the child runs in a terminal

is(output_of('sh', '-c', 'test -t 0 && test -t 1 && test -t 2 && echo all-tty'), "all-tty\r\n", 'stdin, stdout and stderr are terminals') ;
is(output_of('sh', '-c', 'echo to-tty > /dev/tty'), "to-tty\r\n", 'the pty is the controlling terminal') ;
is(output_of('sh', '-c', 'echo out; echo err >&2'), "out\r\nerr\r\n", 'stdout and stderr both reach the master, in order') ;

my ($in, $out, $err) = split ' ', output_of($^X, '-e', 'print join(" ", map { readlink "/proc/self/fd/$_" } 0 .. 2), "\n"') ;

like($in, qr{\A/dev/pts/\d+\z}, 'stdin is a pseudo terminal') ;
is($out, $in, 'stdout is the same terminal as stdin') ;
is($err, $in, 'stderr is the same terminal as stdin') ;

is(output_of($^X, '-e', 'open(my $f, "<", "/proc/$$/stat") or die ; my @f = split " ", <$f> ; print $f[4] == $$ ? "group" : "no", " ", $f[5] == $$ ? "leader" : "no", "\n"'), "group leader\r\n", 'the child is a session and process group leader') ;

my $first  = start_pty('tty') ;
my $second = start_pty('tty') ;
my $tty_a  = read_all($first) ;
my $tty_b  = read_all($second) ;

like($tty_a, qr{\A/dev/pts/\d+\r\n\z}, 'tty reports a pseudo terminal') ;
isnt($tty_a, $tty_b, 'two children have two terminals') ;

$first->wait_exit ;
$second->wait_exit ;

is(output_of($^X, '-MPOSIX', '-e', '$t = POSIX::Termios->new ; $t->getattr(0) ; $l = $t->getlflag ; print(($l & ECHO ? "echo" : "noecho"), " ", ($l & ICANON ? "icanon" : "noicanon"), "\n")'), "echo icanon\r\n", 'the terminal starts in cooked mode with echo') ;
is(output_of('stty', 'size'), "0 0\r\n", 'the window size starts empty') ;

# arguments and environment

is(output_of($^X, '-e', 'print join("|", map { "<$_>" } @ARGV), "\n"', 'a b', '', "c'd", '$HOME', '*', "tab\there"), "<a b>|<>|<c'd>|<\$HOME>|<*>|<tab\there>\r\n", 'arguments are passed as they are, without a shell') ;

like(failure_of(sub { start_pty('echo hi; echo there') ; }), qr/cannot execute 'echo hi; echo there': No such file or directory/, 'a single word command is not given to a shell') ;

{
local $ENV{KEYFILTER_TEST_VALUE} = 'from the parent' ;

is(output_of('sh', '-c', 'echo "$KEYFILTER_TEST_VALUE"'), "from the parent\r\n", 'the environment is inherited') ;
}

is(output_of('sh', '-c', 'echo "${KEYFILTER_TEST_VALUE:-unset}"'), "unset\r\n", 'and reflects the parent at spawn time') ;

my $cwd = Cwd::getcwd() ;

is(output_of('pwd'), "$cwd\r\n", 'the working directory is inherited') ;

{
local $ENV{TERM} = 'xterm-256color' ;

is(output_of('sh', '-c', 'echo $TERM'), "xterm-256color\r\n", 'TERM is inherited') ;
}

SKIP:
	{
	skip 'no /proc', 1 unless -d '/proc/self/fd' ;
	
	my $program = 'opendir(my $d, "/proc/self/fd") or die ; print join(" ", sort { $a <=> $b } grep { /^\d+$/ && $_ != fileno($d) } readdir $d), "\n"' ;
	
	is(output_of($^X, '-e', $program), "0 1 2\r\n", 'no other file descriptor leaks into the child') ;
	}

{
local $SIG{INT}  = 'IGNORE' ;
local $SIG{PIPE} = 'IGNORE' ;

my $child  = start_pty($^X, '-e', 'kill "INT", $$ ; sleep 1 ; print "survived\n"') ;
my $output = read_all($child) ;

unlike($output, qr/survived/, 'an ignored signal in the parent is not ignored by the child') ;
is($child->wait_exit, 130, 'the child dies of the default action') ;
}

# failures to execute

like(failure_of(sub { start_pty('no-such-command-xyz') ; }), qr/\Acannot execute 'no-such-command-xyz': No such file or directory\n\z/, 'a missing program is fatal and the message says why') ;

my $dir = temp_dir() ;

write_file("$dir/not-executable", "#!/bin/sh\necho hi\n") ;
chmod 0644, "$dir/not-executable" ;

like(failure_of(sub { start_pty("$dir/not-executable") ; }), qr/cannot execute '\Q$dir\E\/not-executable': Permission denied/, 'a file that is not executable is fatal') ;
like(failure_of(sub { start_pty($dir) ; }), qr/cannot execute '\Q$dir\E': Permission denied/, 'a directory is fatal') ;
like(failure_of(sub { start_pty("$dir/missing/program") ; }), qr/cannot execute .*: No such file or directory/, 'a missing directory is fatal') ;

my $broken = KeyFilter::PTY->new(command => ['no-such-command-xyz']) ;

failure_of(sub { $broken->spawn ; }) ;

ok(!defined $broken->pid, 'a failed spawn leaves no pid') ;
ok(!defined $broken->master, 'and no pty') ;
is(waitpid(-1, POSIX::WNOHANG()), -1, 'and no zombie') ;
like(failure_of(sub { $broken->spawn ; }), qr/cannot execute 'no-such-command-xyz'/, 'a failed spawn can be tried again') ;

# signals and lifetime

my $sleeper = start_pty('sleep', '30') ;

is($sleeper->is_running, 1, 'a running child is running') ;
ok($sleeper->signal('TERM'), 'a signal is sent to the child') ;
is($sleeper->wait_exit, 143, 'the child died of the signal') ;
is($sleeper->is_running, 0, 'and is no longer running') ;

my $group = start_pty('sh', '-c', 'sleep 30 & echo $! ; wait') ;
my $line  = read_until($group->master, qr/\d+\r\n/) ;

my ($background) = $line =~ /(\d+)/ ;

ok($background > 0, 'the shell started a background process') ;

$group->signal('TERM') ;

is($group->wait_exit, 143, 'the shell died of the signal') ;
ok(process_gone($background), 'the signal went to the whole process group') ;

ok(!defined(failure_of(sub { $sleeper->close_master ; $sleeper->close_master ; })), 'close_master can be called twice') ;

like(failure_of(sub { KeyFilter::PTY->new(command => ['true'])->signal('TERM') ; }), qr/child not spawned/, 'a signal needs a child') ;
like(failure_of(sub { KeyFilter::PTY->new(command => ['true'])->wait_exit ; }), qr/child not spawned/, 'waiting needs a child') ;

# several children

my @children = map { start_pty('sh', '-c', "echo $_ ; sleep 0.2 ; echo $_") } 1 .. 8 ;
my @outputs  = map { read_all($_) } @children ;

is_deeply(\@outputs, [ map { "$_\r\n$_\r\n" } 1 .. 8 ], 'several children run at once, each with its own terminal') ;

$_->wait_exit for @children ;

# no leaks

SKIP:
	{
	skip 'no /proc', 1 unless -d '/proc/self/fd' ;
	
	my $count = sub { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; } ;
	my $before = $count->() ;
	
	for (1 .. 20)
		{
		my $child = start_pty('true') ;
		
		read_all($child) ;
		$child->wait_exit ;
		$child->close_master ;
		}
	
	is($count->(), $before, 'spawning and closing leaves no file descriptor open') ;
	}

done_testing ;
