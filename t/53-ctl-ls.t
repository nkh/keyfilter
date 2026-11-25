#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $script  = "$FindBin::Bin/../keyfilter" ;
my $home    = temp_dir() ;
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

# nothing running

my $none = ctl('ls') ;

is($none->{out}, '', 'without instances ls lists nothing') ;
is($none->{err}, '', 'and says nothing') ;
is($none->{code}, 0, 'it is not an error') ;

# instances

my @alive = map { sleeper() } 1 .. 3 ;
my ($low, $middle, $high) = sort { $a <=> $b } @alive ;

my @controls = (
	KeyFilter::Control->new(dir => $sockets, pid => $high, info => { command => 'vim notes.txt' }),
	KeyFilter::Control->new(dir => $sockets, pid => $low, info => { command => 'bash' }),
	KeyFilter::Control->new(dir => $sockets, pid => $middle, info => { command => 'ssh -t host "tmux attach"' }),
	) ;

my $list = ctl('ls') ;

is($list->{out}, "$low bash\n$middle ssh -t host \"tmux attach\"\n$high vim notes.txt\n", 'ls lists the pid and the command of each instance, sorted by pid') ;
is($list->{code}, 0, 'and succeeds') ;
is($list->{err}, '', 'without a message') ;

my $nameless = KeyFilter::Control->new(dir => $sockets, pid => $$) ;

like(ctl('ls')->{out}, qr/^\Q$$\E \(unknown\)$/m, 'an instance without information has an unknown command') ;

$nameless->close ;

my $gone = fork() ;

POSIX::_exit(0) if $gone == 0 ;

waitpid($gone, 0) ;

my $stale = KeyFilter::Control->new(dir => $sockets, pid => $gone, info => { command => 'stale' }) ;

unlike(ctl('ls')->{out}, qr/stale/, 'an instance whose process is gone is not listed') ;

$stale->close ;

kill 'KILL', $middle ;
waitpid($middle, 0) ;

is(ctl('ls')->{out}, "$low bash\n$high vim notes.txt\n", 'an instance that ends is not listed any more') ;

my $other = KeyFilter::Control->new(dir => $sockets, pid => getppid(), info => { command => "line\nbreak and\ttab" }) ;

like(ctl('ls')->{out}, qr/^\Q@{[ getppid() ]}\E line break and tab$/m, 'a command is always on one line') ;

$other->close ;

# the arguments

is(ctl('ls', 'extra')->{err}, "keyfilterctl: ls takes no argument\n", 'ls takes no argument') ;
is(ctl('ls', 'extra')->{code}, 1, 'which is a usage error') ;
is(ctl('ls', 'extra')->{out}, '', 'with no output') ;

is(ctl('--pid', $low, 'ls')->{out}, "$low bash\n$high vim notes.txt\n", 'ls lists all the instances, a pid does not select one') ;
is(ctl('-p', $low, 'ls')->{code}, 0, 'the short option works') ;
is(ctl("--pid=$low", 'ls')->{code}, 0, 'so does the form with an equal sign') ;

for my $bad (['--pid'], ['--pid', 'abc', 'ls'], ['--pid', '0', 'ls'], ['--pid', '-5', 'ls'], ['--pid=', 'ls'], ['-p'], ['--pid', '1.5', 'ls'])
	{
	my $failed = ctl(@$bad) ;
	
	is($failed->{err}, "keyfilterctl: option '--pid' needs a pid\n", "refused: @$bad") ;
	is($failed->{code}, 1, 'with a usage code') ;
	}

# usage

my $usage = ctl() ;

is($usage->{err}, KeyFilter::Ctl::usage(), 'no command gives the usage') ;
is($usage->{code}, 1, 'and a usage code') ;
like($usage->{err}, qr/\AUsage: keyfilterctl \[--pid PID\] command \[arguments\]\nTry 'keyfilterctl --help'/, 'which says how to get help') ;

my $unknown = ctl('frobnicate') ;

is($unknown->{err}, "keyfilterctl: unknown command 'frobnicate'\n", 'an unknown command is refused') ;
is($unknown->{code}, 1, 'with a usage code') ;
is(ctl('--bogus', 'ls')->{err}, "keyfilterctl: unknown option '--bogus'\n", 'so is an unknown option') ;
is(ctl('LS')->{err}, "keyfilterctl: unknown command 'LS'\n", 'commands are in lower case') ;

my $help = ctl('--help') ;

is($help->{out}, KeyFilter::Ctl::help_text(), '--help shows the help') ;
is($help->{code}, 0, 'and succeeds') ;
is(ctl('-h')->{out}, $help->{out}, '-h is the same') ;
is(ctl('ls', '--help')->{err}, "keyfilterctl: ls takes no argument\n", 'a help option after the command is an argument of the command') ;
like($help->{out}, qr/\AUsage: keyfilterctl \[--pid PID\] command/, 'the help starts with the usage') ;
like($help->{out}, qr/^  ls /m, 'and describes ls') ;
like($help->{out}, qr/--pid/, 'and --pid') ;

$_->close for @controls ;

kill 'KILL', $low, $high ;
waitpid($_, 0) for $low, $high ;

# the real thing, started by name

symlink($script, "$dir/keyfilterctl") or die "symlink: $!" ;

my $real_home = temp_dir() ;
my $child     = fork() ;

if ($child == 0)
	{
	$ENV{HOME} = "$real_home" ;
	
	open(STDIN, '<', '/dev/null') ;
	open(STDOUT, '>', '/dev/null') ;
	open(STDERR, '>', '/dev/null') ;
	
	exec $^X, $script, '--', 'sleep', '2.5' ;
	}

my $deadline = Time::HiRes::time() + 10 ;

Time::HiRes::sleep(0.05) until (-d "$real_home/.config/keyfilter/sockets" && glob("$real_home/.config/keyfilter/sockets/*.sock")) || Time::HiRes::time() > $deadline ;

my $listed = qx{HOME=$real_home $dir/keyfilterctl ls 2>&1} ;

is($listed, "$child sleep 2.5\n", 'keyfilterctl, started under that name, lists the keyfilter that runs') ;
is($? >> 8, 0, 'and ends with 0') ;

is(qx{HOME=$real_home $dir/keyfilterctl 2>&1}, KeyFilter::Ctl::usage(), 'the usage is the one of keyfilterctl') ;
is(qx{HOME=$real_home $dir/keyfilterctl --help}, KeyFilter::Ctl::help_text(), 'and so is the help') ;
like(qx{HOME=$real_home $script --help}, qr/keyfilterctl/, 'while keyfilter itself talks about keyfilterctl') ;

waitpid($child, 0) ;

is(qx{HOME=$real_home $dir/keyfilterctl ls 2>&1}, '', 'when the instance ends it is not listed') ;

done_testing ;
