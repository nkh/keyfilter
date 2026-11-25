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

my @cases =
	(
	[['block', 'C-z'], { cmd => 'block', keys => ["\x1a"] }],
	[['block', 'C-z', 'C-c', 'Up'], { cmd => 'block', keys => ["\x1a", "\x03", "\e[A"] }],
	[['block', 'a b'], { cmd => 'block', keys => ['a', 'b'] }],
	[['block', 'M-a', '1b5b41', 'F5'], { cmd => 'block', keys => ["\ea", "\e[A", "\e[15~"] }],
	[['block', '\#'], { cmd => 'block', keys => ['#'] }],
	[['unblock', 'C-z'], { cmd => 'unblock', keys => ["\x1a"] }],
	[['unblock', 'a', 'b'], { cmd => 'unblock', keys => ['a', 'b'] }],
	[['map', 'a=b'], { cmd => 'map', key => 'a', replacement => 'b' }],
	[['map', 'F1=<<Enter>>'], { cmd => 'map', key => "\eOP", replacement => "\r" }],
	[['map', 'F5=git status\n'], { cmd => 'map', key => "\e[15~", replacement => "git status\n" }],
	[['map', 'M-b=<<C-t>>'], { cmd => 'map', key => "\eb", replacement => "\x14" }],
	[['map', 'a=one', 'two'], { cmd => 'map', key => 'a', replacement => 'one two' }],
	[['map', 'a='], { cmd => 'map', key => 'a', replacement => '' }],
	[['map', '==x'], { cmd => 'map', key => '=', replacement => 'x' }],
	[['map', 'a=\#'], { cmd => 'map', key => 'a', replacement => '#' }],
	[['map', 'a=x # a comment'], { cmd => 'map', key => 'a', replacement => 'x' }],
	) ;

for my $case (@cases)
	{
	my ($arguments, $expected) = @$case ;
	
	my $result = ctl(@$arguments) ;
	
	is($result->{code}, 0, "succeeds: @$arguments") ;
	is($result->{out} . $result->{err}, '', 'with no message') ;
	
	my @received = received_by($control) ;
	
	is_deeply(\@received, [$expected], 'the instance receives the command') ;
	}

is(ctl('block', 'a')->{code}, 0, 'commands can follow each other') ;
is(ctl('map', 'b=c')->{code}, 0, 'of any kind') ;
is(ctl('unblock', 'a')->{code}, 0, 'one after the other') ;

is_deeply([ map { $_->{cmd} } received_by($control) ], ['block', 'map', 'unblock'], 'and arrive in order') ;

# what is refused

for my $case (
	[['block'], qr/\Akeyfilterctl: block requires an argument\n\z/],
	[['block', ''], qr/\Akeyfilterctl: block requires an argument\n\z/],
	[['block', '  '], qr/\Akeyfilterctl: block requires an argument\n\z/],
	[['unblock'], qr/\Akeyfilterctl: unblock requires an argument\n\z/],
	[['map'], qr/\Akeyfilterctl: map requires an argument\n\z/],
	[['block', 'bogus'], qr/\Akeyfilterctl: unknown key specification 'bogus'\n\z/],
	[['block', 'C-z', 'bogus'], qr/\Akeyfilterctl: unknown key specification 'bogus'\n\z/],
	[['unblock', 'C-1'], qr/\Akeyfilterctl: key specification 'C-1' has no control character\n\z/],
	[['block', 'C-Enter'], qr/\Akeyfilterctl: modifier C is not supported for key specification 'C-Enter', use a raw sequence\n\z/],
	[['block', "a\nb"], qr/\Akeyfilterctl: the text cannot contain a line end/],
	[['map', 'a'], qr/\Akeyfilterctl: invalid syntax, expected: map KEY=REPLACEMENT\n\z/],
	[['map', 'bogus=x'], qr/\Akeyfilterctl: unknown key specification 'bogus'\n\z/],
	[['map', 'a=<<nokey>>'], qr/\Akeyfilterctl: unknown key specification 'nokey'\n\z/],
	[['map', 'a=<<Enter'], qr/\Akeyfilterctl: unterminated key symbol/],
	[['map', 'a=\q'], qr/\Akeyfilterctl: unknown escape/],
	[['map', 'a = b'], qr/\Akeyfilterctl: invalid syntax/],
	[['map', 'a=' . ('x' x 70000)], qr/\Akeyfilterctl: the command is too long\n\z/],
	)
	{
	my ($arguments, $pattern) = @$case ;
	
	my $failed = ctl(@$arguments) ;
	
	like($failed->{err}, $pattern, 'refused: ' . substr(join(' ', @$arguments), 0, 40) =~ s/\s/ /gr) ;
	is($failed->{code}, 1, 'with a usage code') ;
	is($failed->{out}, '', 'and no output') ;
	}

is_deeply([ received_by($control) ], [], 'nothing of what was refused reached the instance') ;

# choosing the instance

my $other_pid     = sleeper() ;
my $other_control = KeyFilter::Control->new(dir => $sockets, pid => $other_pid, info => { command => 'vim' }) ;

for my $command ('block a', 'unblock a', 'map a=b')
	{
	my @words = split ' ', $command ;
	
	is(ctl(@words)->{code}, 2, "with several instances and no pid $words[0] fails") ;
	is(ctl('--pid', $other_pid, @words)->{code}, 0, 'with --pid it works') ;
	is(scalar(() = received_by($other_control)), 1, 'the instance that was chosen gets it') ;
	is(scalar(() = received_by($control)), 0, 'and the other does not') ;
	}

$other_control->close ;
$control->close ;
kill 'KILL', $alive, $other_pid ;
waitpid($_, 0) for $alive, $other_pid ;

is(ctl('block', 'a')->{err}, "keyfilterctl: no keyfilter instance is running\n", 'without an instance a rule cannot be sent') ;
is(ctl('map', 'a=b')->{code}, 2, 'with status 2') ;

# a running keyfilter

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

write_file("$home/.config/keyfilter/base.profile", "map a=p\n", "map x=profile\n") ;

my $instance = start_instance($home, '--profile', 'base', '--', 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 19') ;

like(read_until($instance->{out}, qr/ready\n/, 10), qr/ready/, 'a keyfilter runs') ;

sub typed_after
{
my ($command, $keys) = @_ ;

system("HOME=$home $dir/keyfilterctl $command") if length $command ;

Time::HiRes::sleep(0.3) ;

syswrite($instance->{in}, $keys) ;

Time::HiRes::sleep(0.2) ;

return ;
}

# -----------------------------------------------------------------------------

typed_after('', 'a') ;
typed_after('block a', 'a') ;
typed_after('unblock a', 'a') ;
typed_after("map a=2", 'a') ;
typed_after("map F5='git status\\n'", "\e[15~") ;
typed_after('map M-b=Q', "\eb") ;
typed_after("block F5 M-b", "\e[15~\eb") ;
typed_after('unblock M-b', "\eb") ;
typed_after('map x=1 2', 'x') ;

is(read_all($instance->{out}), 'p' . '' . 'p' . '2' . "git status\n" . 'Q' . 'Q' . '1 2', 'what is typed is filtered by the rules that were sent before it: a profile map, a block, an unblock, a map that overrides the profile, a map of a sequence, a block of two keys, an unblock, a map with a space') ;

waitpid($instance->{pid}, 0) ;

done_testing ;
