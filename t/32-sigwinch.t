#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir     = temp_dir() ;
my $counter = 0 ;

sub wait_for_content
{
my ($path, $pattern, $timeout) = @_ ;

my $deadline = Time::HiRes::time() + ($timeout // 10) ;

while (Time::HiRes::time() < $deadline)
	{
	my $text = -e $path ? read_file($path) : '' ;
	
	return $text if $text =~ $pattern ;
	
	Time::HiRes::sleep(0.02) ;
	}

return -e $path ? read_file($path) : '' ;
}

# -----------------------------------------------------------------------------

sub terminal_with_size
{
my (@size) = @_ ;

my ($terminal, $slave) = new_terminal() ;

$terminal->set_winsize(@size) ;

return ($terminal, $slave) ;
}

# -----------------------------------------------------------------------------

# the child starts with the size of the terminal of the user

for my $size ([24, 80, 0, 0], [50, 132, 0, 0], [1, 1, 0, 0], [200, 300, 0, 0], [60, 220, 0, 0])
	{
	my ($terminal, $slave) = terminal_with_size(@$size) ;
	
	my $engine = engine_process({ tty_input => $slave }, 'stty', 'size') ;
	
	is($engine->read_all, "$size->[0] $size->[1]\r\n", "the child starts with $size->[0] rows and $size->[1] columns") ;
	is($engine->finish, 0, 'and ends') ;
	}

# pixels are copied too

my ($terminal, $slave) = terminal_with_size(40, 100, 800, 600) ;

my $pty = KeyFilter::PTY->new(command => ['sleep', '10'], input => $slave, output => do { open(my $null, '>', '/dev/null') ; $null }) ;

$pty->spawn ;

is_deeply([ $pty->master->get_winsize ], [40, 100, 800, 600], 'the whole size, pixels included, is given to the child terminal') ;

$terminal->set_winsize(30, 90, 700, 500) ;

is($pty->sync_window_size, 1, 'sync_window_size reports success on a terminal') ;
is_deeply([ $pty->master->get_winsize ], [30, 90, 700, 500], 'and copies the new size') ;

$terminal->set_winsize(31, 91, 0, 0) ;
$pty->wake('W') ;

is($pty->pump(0), 1, 'a window event is handled') ;
is_deeply([ $pty->master->get_winsize ], [31, 91, 0, 0], 'and copies the size') ;

$terminal->set_winsize(32, 92, 0, 0) ;

is($pty->window_changed, 1, 'window_changed copies the size') ;
is_deeply([ $pty->master->get_winsize ], [32, 92, 0, 0], 'the same way') ;

$pty->signal('KILL') ;

# no terminal, no size

my ($input, $writer) = pipe_pair() ;

my $plain = KeyFilter::PTY->new(command => ['sleep', '10'], input => $input) ;

is($plain->sync_window_size, 0, 'without a master there is nothing to sync') ;

$plain->spawn ;

is($plain->sync_window_size, 0, 'a pipe has no size') ;
is($plain->window_changed, 0, 'and a window event changes nothing') ;
is_deeply([ $plain->master->get_winsize ], [0, 0, 0, 0], 'the child terminal keeps an empty size') ;

$plain->signal('KILL') ;

open(my $file, '<', $0) or die ;

is(KeyFilter::PTY::copy_window_size($plain->master, $file), 0, 'a file has no size') ;
is(KeyFilter::PTY::copy_window_size(undef, $slave), 0, 'without a master nothing is copied') ;
is(KeyFilter::PTY::copy_window_size($plain->master, undef), 0, 'without an input nothing is copied') ;

close $file ;

is(KeyFilter::PTY::copy_window_size($plain->master, $file), 0, 'a closed file has no size') ;

my $no_tty = engine_process({}, 'stty', 'size') ;

is($no_tty->read_all, "0 0\r\n", 'a child whose input is not a terminal sees an empty size') ;
is($no_tty->finish, 0, 'and runs normally') ;

# the size follows the terminal of the user while the child runs

($terminal, $slave) = terminal_with_size(24, 80) ;

my $log    = "$dir/log" . ++$counter ;
my $script = "trap 'stty size >> $log' WINCH ; echo ready ; while : ; do sleep 0.05 ; done" ;
my $live   = engine_process({ tty_input => $slave }, 'sh', '-c', $script) ;

like(read_until($live->{output}, qr/ready\r\n/), qr/ready/, 'the child is running') ;

$terminal->set_winsize(30, 100) ;
$live->signal('WINCH') ;

is(wait_for_content($log, qr/30 100/), "30 100\n", 'a resize reaches the child') ;

$terminal->set_winsize(45, 150) ;
$live->signal('WINCH') ;

is(wait_for_content($log, qr/45 150/), "30 100\n45 150\n", 'and the next one too') ;

$terminal->set_winsize(10, 40) ;
$live->signal('WINCH') ;

is(wait_for_content($log, qr/10 40/), "30 100\n45 150\n10 40\n", 'in order') ;

$live->signal('WINCH') ;

Time::HiRes::sleep(0.6) ;

is(read_file($log), "30 100\n45 150\n10 40\n", 'a window event without a change does not disturb the child') ;

$live->signal('TERM') ;

is($live->finish, 143, 'the child ends') ;

# without a signal the size does not change

($terminal, $slave) = terminal_with_size(24, 80) ;

$log  = "$dir/log" . ++$counter ;
$live = engine_process({ tty_input => $slave }, 'sh', '-c', "trap 'stty size >> $log' WINCH ; echo ready ; while : ; do sleep 0.05 ; done") ;

read_until($live->{output}, qr/ready\r\n/) ;

$terminal->set_winsize(70, 70) ;

Time::HiRes::sleep(0.5) ;

ok(!-e $log, 'the child is not told about a size it was not told to read') ;

$live->signal('WINCH') ;

is(wait_for_content($log, qr/70 70/), "70 70\n", 'until the engine gets the signal') ;

$live->signal('TERM') ;
$live->finish ;

# with a pipe as input a window signal is harmless

my $pipe_engine = engine_process({}, 'sh', '-c', 'echo ready ; sleep 0.5 ; echo done ; exit 3') ;

read_until($pipe_engine->{output}, qr/ready\r\n/) ;

$pipe_engine->signal('WINCH') ;
$pipe_engine->signal('WINCH') ;

like($pipe_engine->read_all, qr/done/, 'window signals do not disturb a child that has no terminal behind it') ;
is($pipe_engine->finish, 3, 'and its exit code') ;

# the handler goes away with the run

{
local $SIG{WINCH} = 'IGNORE' ;

run_engine({}, 'true') ;

is($SIG{WINCH}, 'IGNORE', 'the WINCH setting is restored when run ends') ;
}

{
local $SIG{WINCH} ;

run_engine({}, 'true') ;

ok(!defined $SIG{WINCH} || $SIG{WINCH} eq 'DEFAULT', 'and a missing setting stays missing') ;
}

done_testing ;
