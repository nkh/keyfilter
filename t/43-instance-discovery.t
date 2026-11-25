#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $home = temp_dir() ;
my $dir  = "$home/sockets" ;

sub mode_of { return (stat $_[0])[2] & 07777 ; }

# -----------------------------------------------------------------------------

sub pids_of { return map { $_->{pid} } @_ ; }

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

sub dead_pid
{
my $pid = fork() ;

POSIX::_exit(0) if $pid == 0 ;

waitpid($pid, 0) ;

return $pid ;
}

# -----------------------------------------------------------------------------

# nobody home

is_deeply([ KeyFilter::Control::instances("$home/nothing") ], [], 'a missing directory has no instance') ;

mkdir $dir or die ;

is_deeply([ KeyFilter::Control::instances($dir) ], [], 'an empty directory has none') ;

# an instance

my $control = KeyFilter::Control->new(dir => $dir) ;
my @found   = KeyFilter::Control::instances($dir) ;

is(scalar @found, 1, 'a control is an instance') ;
is($found[0]{pid}, $$, 'with its pid') ;
is($found[0]{socket}, "$dir/$$.sock", 'and its socket') ;
is_deeply($found[0]{info}, {}, 'and no information when it has none') ;
ok(!-e $control->info_path, 'no information file is written without information') ;

$control->close ;

is_deeply([ KeyFilter::Control::instances($dir) ], [], 'a control that is closed is not an instance') ;

# information

my %info = (command => 'bash -l', started => 1700000000, profiles => 'common vim') ;

$control = KeyFilter::Control->new(dir => $dir, info => \%info) ;

is($control->info_path, "$dir/$$.info", 'the information file is named after the pid') ;
is(read_file($control->info_path), "command: bash -l\nprofiles: common vim\nstarted: 1700000000\n", 'it has one line for each item, in the order of the names') ;
is(mode_of($control->info_path), 0600, 'and is private') ;

@found = KeyFilter::Control::instances($dir) ;

is_deeply($found[0]{info}, { command => 'bash -l', started => '1700000000', profiles => 'common vim' }, 'the information is read back') ;

$control->close ;

ok(!-e "$dir/$$.info", 'closing removes the information file') ;

$control = KeyFilter::Control->new(dir => $dir, info => { command => "two\nlines\tand tab", empty => undef, 'long-key' => 'a: b: c' }) ;

is(read_file($control->info_path), "command: two lines and tab\nempty: \nlong-key: a: b: c\n", 'line ends and controls in a value are replaced by spaces') ;

@found = KeyFilter::Control::instances($dir) ;

is_deeply($found[0]{info}, { command => 'two lines and tab', empty => '', 'long-key' => 'a: b: c' }, 'a value may contain colons, and be empty') ;

$control->close ;

write_file("$dir/$$.info", "# comment\n", "garbage line\n", "ok: 1\n", "  indented: no\n", "\n", "spaced :  no\n", "tabbed:\tyes  \r\n", "9bad: x\n", "dup: first\n", "dup: second\n") ;

$control = KeyFilter::Control->new(dir => $dir) ;

is_deeply(KeyFilter::Control::read_info("$dir/$$.info"), { ok => 1, tabbed => 'yes', dup => 'second' }, 'lines that are not items are ignored, the last of an item wins') ;
is_deeply(KeyFilter::Control::read_info("$dir/missing.info"), {}, 'a missing file has no information') ;

$control->close ;

# instances that are gone

my $alive = sleeper() ;
my $gone  = dead_pid() ;

my $live_control  = KeyFilter::Control->new(dir => $dir, pid => $alive, info => { command => 'alive' }) ;
my $stale_control = KeyFilter::Control->new(dir => $dir, pid => $gone, info => { command => 'gone' }) ;

ok(-S "$dir/$gone.sock", 'the socket of a process that is gone is still there') ;
is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], [$alive], 'but it is not an instance, the pid is validated') ;

kill 'KILL', $alive ;
waitpid($alive, 0) ;

is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], [], 'a process that ends stops being an instance') ;

my $zombie = fork() ;

POSIX::_exit(0) if $zombie == 0 ;

Time::HiRes::sleep(0.3) ;

my $zombie_control = KeyFilter::Control->new(dir => $dir, pid => $zombie) ;

SKIP:
	{
	skip 'no /proc', 1 unless -r "/proc/$zombie/stat" ;
	
	is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], [], 'a process that ended and was not reaped is not an instance') ;
	}

waitpid($zombie, 0) ;

for my $held ($live_control, $stale_control, $zombie_control)
	{
	$held->close ;
	}

# pids

ok(KeyFilter::Control::pid_alive($$), 'this process is alive') ;
ok(KeyFilter::Control::pid_alive(getppid()), 'so is its parent') ;
ok(KeyFilter::Control::pid_alive(1), 'the first process is alive, even when it is not ours') ;
ok(!KeyFilter::Control::pid_alive(dead_pid()), 'a process that was reaped is not') ;

for my $bad (0, -1, 'abc', '12abc', '', undef, '1.5', ' 5', '99999999999')
	{
	ok(!KeyFilter::Control::pid_alive($bad), 'not a pid: ' . ($bad // 'undef')) ;
	}

# what is in the directory

my @live = map { sleeper() } 1 .. 3 ;
my @sorted = sort { $a <=> $b } @live ;
my @controls = map { KeyFilter::Control->new(dir => $dir, pid => $_) } reverse @live ;

is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], \@sorted, 'instances are sorted by pid, as numbers') ;

my $found = KeyFilter::Control::instance($sorted[1], $dir) ;

is($found->{pid}, $sorted[1], 'one instance can be found by its pid') ;
is($found->{socket}, "$dir/$sorted[1].sock", 'with its socket') ;
is(KeyFilter::Control::instance($gone, $dir), undef, 'a pid that is gone is not found') ;
is(KeyFilter::Control::instance(1, $dir), undef, 'neither is a pid without a socket') ;
is(KeyFilter::Control::instance('abc', $dir), undef, 'neither is a name') ;
is(KeyFilter::Control::instance(undef, $dir), undef, 'neither is nothing') ;

write_file("$dir/abc.sock", "x") ;
write_file("$dir/$sorted[0].sock.bak", "x") ;
write_file("$dir/$sorted[0].txt", "x") ;
write_file("$dir/99999999.sock", "not a socket") ;
mkdir "$dir/13.sock" or die ;

is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], \@sorted, 'other names, files that are not sockets and directories are ignored') ;

# cleaning

my $gone_a = dead_pid() ;
my $gone_b = dead_pid() ;

KeyFilter::Control->new(dir => $dir, pid => $gone_a, info => { command => 'a' }) ;
KeyFilter::Control->new(dir => $dir, pid => $gone_b) ;

write_file("$dir/$gone_a.info", "command: a\n") ;
write_file("$dir/77777777.info", "command: orphan\n") ;

my @removed = KeyFilter::Control::remove_stale($dir) ;

is_deeply(\@removed, [ sort { $a <=> $b } $gone_a, $gone_b, 77777777, 99999999 ], 'stale files are removed, the pids are reported') ;
ok(!-e "$dir/$gone_a.sock" && !-e "$dir/$gone_a.info" && !-e "$dir/$gone_b.sock", 'sockets and information of processes that are gone are removed') ;
is_deeply([ pids_of(KeyFilter::Control::instances($dir)) ], \@sorted, 'live instances are kept') ;
ok(-e "$dir/abc.sock", 'files that are not about an instance are kept') ;
is_deeply([ KeyFilter::Control::remove_stale($dir) ], [], 'cleaning twice removes nothing more') ;
is_deeply([ KeyFilter::Control::remove_stale("$home/missing") ], [], 'a missing directory has nothing to clean') ;

# the default directory

{
local $ENV{HOME} = "$home" ;

my $default = KeyFilter::Control->new() ;

is_deeply([ pids_of(KeyFilter::Control::instances()) ], [$$], 'without a directory the socket directory of the user is used') ;

$default->close ;

is_deeply([ KeyFilter::Control::instances() ], [], 'and is empty again') ;
}

kill 'KILL', @live ;
waitpid($_, 0) for @live ;

$_->close for @controls ;

done_testing ;
