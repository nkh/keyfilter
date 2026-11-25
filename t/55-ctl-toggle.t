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

my $sent = ctl('toggle', 'gaming') ;

is($sent->{code}, 0, 'toggle succeeds') ;
is($sent->{out}, '', 'and prints nothing') ;
is($sent->{err}, '', 'nor a message') ;

is_deeply([ received_by($control) ], [{ cmd => 'toggle', profile => 'gaming' }], 'the instance receives a toggle command with the name of the profile') ;

for my $name ('vim', 'my-profile', 'a.b', '/home/me/x.profile', './local.profile', '../up/y.profile', 'UPPER', 'with_underscore', 'caf' . "\xc3\xa9")
	{
	is(ctl('toggle', $name)->{code}, 0, "toggle $name succeeds") ;
	
	my ($command) = received_by($control) ;
	
	is($command->{profile}, $name, 'and the name arrives as it is') ;
	}

is(ctl('toggle', 'a')->{code}, 0, 'toggle can follow toggle') ;
is(ctl('toggle', 'b')->{code}, 0, 'one after the other') ;
is_deeply([ map { $_->{profile} } received_by($control) ], ['a', 'b'], 'and they arrive in order') ;

# what is refused

for my $case (
	[['toggle'], qr/\Akeyfilterctl: toggle takes one profile name\n\z/],
	[['toggle', ''], qr/\Akeyfilterctl: toggle takes one profile name\n\z/],
	[['toggle', 'a', 'b'], qr/\Akeyfilterctl: toggle takes one profile name\n\z/],
	[['toggle', 'two words'], qr/\Akeyfilterctl: a profile name cannot contain a space or a #\n\z/],
	[['toggle', "tab\there"], qr/cannot contain a space or a #/],
	[['toggle', "new\nline"], qr/cannot contain a space or a #/],
	[['toggle', 'a#b'], qr/cannot contain a space or a #/],
	[['toggle', 'keyfilter_runtime'], qr/\Akeyfilterctl: reserved profile name 'keyfilter_runtime'\n\z/],
	[['toggle', 'keyfilter_command_line'], qr/\Akeyfilterctl: reserved profile name 'keyfilter_command_line'\n\z/],
	)
	{
	my ($arguments, $pattern) = @$case ;
	
	my $failed = ctl(@$arguments) ;
	
	like($failed->{err}, $pattern, 'refused: ' . join(' ', @$arguments) =~ s/\s/ /gr) ;
	is($failed->{code}, 1, 'with a usage code') ;
	is($failed->{out}, '', 'and no output') ;
	}

is_deeply([ received_by($control) ], [], 'nothing of what was refused reached the instance') ;

# choosing the instance

my $other_pid     = sleeper() ;
my $other_control = KeyFilter::Control->new(dir => $sockets, pid => $other_pid, info => { command => 'vim' }) ;

my $ambiguous = ctl('toggle', 'x') ;

is($ambiguous->{code}, 2, 'with several instances and no pid toggle fails') ;
like($ambiguous->{err}, qr/\Akeyfilterctl: several keyfilter instances are running \(pids \d+, \d+\), choose one with --pid\n\z/, 'and says so') ;

is(ctl('--pid', $other_pid, 'toggle', 'x')->{code}, 0, '--pid chooses the instance') ;
is_deeply([ map { $_->{profile} } received_by($other_control) ], ['x'], 'which gets the command') ;
is_deeply([ received_by($control) ], [], 'and the other does not') ;
is(ctl('toggle', 'x', '--pid', $alive)->{code}, 1, 'the options come before the command') ;

is(ctl('--pid', '999999', 'toggle', 'x')->{err}, "keyfilterctl: no keyfilter instance has the pid 999999\n", 'a pid that is not an instance is refused') ;

$other_control->close ;
$control->close ;
kill 'KILL', $alive, $other_pid ;
waitpid($_, 0) for $alive, $other_pid ;

is(ctl('toggle', 'x')->{err}, "keyfilterctl: no keyfilter instance is running\n", 'without an instance toggle fails') ;
is(ctl('toggle', 'x')->{code}, 2, 'with status 2') ;

# a running keyfilter with profiles

sub start_instance
{
my ($home, @options) = @_ ;

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
	
	exec $^X, $script, @options ;
	}

close $write ;
close $stdin_read ;

my $deadline = Time::HiRes::time() + 10 ;

Time::HiRes::sleep(0.05) until (-d "$home/.config/keyfilter/sockets" && glob("$home/.config/keyfilter/sockets/*.sock")) || Time::HiRes::time() > $deadline ;

return { pid => $pid, out => $read, in => $stdin_write } ;
}

# -----------------------------------------------------------------------------

symlink($script, "$dir/keyfilterctl") or die "symlink: $!" ;

my $home = temp_dir() ;

write_file("$home/.config/keyfilter/base.profile", "map a=1\n", "map z=z\n") ;
write_file("$home/.config/keyfilter/gaming.profile", "map a=2\n") ;
write_file("$home/.config/keyfilter/late.profile", "map a=3\n") ;

my $instance = start_instance($home, '--profile', 'base', '--', 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 7') ;

like(read_until($instance->{out}, qr/ready\n/, 10), qr/ready/, 'a keyfilter runs with a profile') ;

sub typed_after
{
my ($command, $keys) = @_ ;

if (length $command)
	{
	system("HOME=$home $dir/keyfilterctl $command") ;
	}

Time::HiRes::sleep(0.3) ;

syswrite($instance->{in}, $keys) ;

Time::HiRes::sleep(0.2) ;

return ;
}

# -----------------------------------------------------------------------------

typed_after('', 'a') ;
typed_after('toggle gaming', 'a') ;
typed_after('toggle gaming', 'a') ;
typed_after('toggle gaming', 'a') ;
typed_after('toggle nope', 'a') ;
typed_after('toggle base', 'a') ;
typed_after('toggle late', 'a') ;

is(read_all($instance->{out}), '1212223', 'what is typed is filtered by the profiles that were toggled before it: base, gaming on, off, on, a profile that does not exist changes nothing, base off, late on') ;

waitpid($instance->{pid}, 0) ;

is(qx{HOME=$home $dir/keyfilterctl toggle x 2>&1}, "keyfilterctl: no keyfilter instance is running\n", 'when the instance has ended there is nobody to toggle') ;
is($? >> 8, 2, 'with status 2') ;

done_testing ;
