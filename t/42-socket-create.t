#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use IO::Select () ;
use POSIX () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub fd_count { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; }

# -----------------------------------------------------------------------------

sub mode_of { return (stat $_[0])[2] & 07777 ; }

# -----------------------------------------------------------------------------

sub connect_to { return IO::Socket::UNIX->new(Peer => $_[0], Type => Socket::SOCK_STREAM()) ; }

# -----------------------------------------------------------------------------

my $home = temp_dir() ;

{
local $ENV{HOME} = "$home" ;

is(KeyFilter::Control::socket_dir(), "$home/.config/keyfilter/sockets", 'the socket directory is in the configuration directory of the user') ;
}

{
local $ENV{HOME} ;

delete $ENV{HOME} ;

like(failure_of(sub { KeyFilter::Control::socket_dir() ; }), qr/\AHOME is not set/, 'without a home directory there is no socket directory') ;
}

# creating a socket

my $dir     = "$home/a/b/sockets" ;
my $control = KeyFilter::Control->new(dir => $dir) ;

isa_ok($control, 'KeyFilter::Control') ;
is($control->dir, $dir, 'the directory is kept') ;
is($control->pid, $$, 'the pid is the one of the process') ;
is($control->path, "$dir/$$.sock", 'the socket is named after the pid') ;
ok(-d $dir, 'the directory is created') ;
ok(-d "$home/a/b", 'with the directories above it') ;
is(mode_of($dir), 0700, 'the directory is private') ;
is(mode_of("$home/a"), 0700, 'and so are the directories created above it') ;
ok(-S $control->path, 'the socket exists') ;
is(mode_of($control->path), 0600, 'and is private') ;
isa_ok($control->listener, 'IO::Socket::UNIX') ;
ok(!$control->listener->blocking, 'the listening socket does not block') ;

# talking to it

is($control->accept, undef, 'accept gives nothing when nobody connects') ;

my $client = connect_to($control->path) ;

ok($client, 'a client can connect') ;

my $server ;

IO::Select->new($control->listener)->can_read(2) ;

$server = $control->accept ;

ok($server, 'and the control accepts it') ;

syswrite($client, "block C-z\n") ;

IO::Select->new($server)->can_read(2) ;

sysread($server, my $received, 100) ;

is($received, "block C-z\n", 'what the client writes reaches the control') ;

syswrite($server, "hello\n") ;

sysread($client, my $answer, 100) ;

is($answer, "hello\n", 'and the other way round') ;

my @clients = map { connect_to($control->path) } 1 .. 3 ;

IO::Select->new($control->listener)->can_read(2) ;

my @servers ;

while (my $next = $control->accept)
	{
	push @servers, $next ;
	}

is(scalar @servers, 3, 'several clients are accepted one after the other') ;
is($control->accept, undef, 'and then nothing more') ;

# closing

is($control->close, $control, 'close returns the control') ;
ok(!-e $control->path, 'the socket file is removed') ;
ok(!connect_to($control->path), 'and nobody can connect') ;
is($control->accept, undef, 'a closed control accepts nothing') ;
is($control->close, $control, 'closing twice is fine') ;

# other sockets and files in the directory are not touched

my $first  = KeyFilter::Control->new(dir => $dir, pid => 11111) ;
my $second = KeyFilter::Control->new(dir => $dir, pid => 22222) ;

write_file("$dir/other.txt", "keep\n") ;

ok(-S "$dir/11111.sock" && -S "$dir/22222.sock", 'two controls with two pids live together') ;
is($first->path, "$dir/11111.sock", 'each with its own socket') ;

my $left = connect_to($first->path) ;
my $right = connect_to($second->path) ;

syswrite($left, 'L') ;
syswrite($right, 'R') ;

IO::Select->new($first->listener, $second->listener)->can_read(2) ;

my $on_first  = $first->accept ;
my $on_second = $second->accept ;

sysread($on_first, my $first_data, 10) ;
sysread($on_second, my $second_data, 10) ;

is_deeply([$first_data, $second_data], ['L', 'R'], 'a connection goes to the control it was made for') ;

$first->close ;

ok(!-e "$dir/11111.sock", 'closing one removes its socket') ;
ok(-S "$dir/22222.sock", 'and not the others') ;
is(read_file("$dir/other.txt"), "keep\n", 'nor any other file') ;

$second->close ;

# an old file is replaced

write_file("$dir/33333.sock", "not a socket\n") ;

my $replaced = KeyFilter::Control->new(dir => $dir, pid => 33333) ;

ok(-S $replaced->path, 'a file left under the name of the socket is replaced') ;

$replaced->close ;

my $crashed = fork() ;

if ($crashed == 0)
	{
	KeyFilter::Control->new(dir => $dir, pid => 44444) ;
	
	POSIX::_exit(0) ;
	}

waitpid($crashed, 0) ;

ok(-S "$dir/44444.sock", 'a crashed instance leaves its socket behind') ;
ok(!connect_to("$dir/44444.sock"), 'which nobody can connect to') ;

my $again = KeyFilter::Control->new(dir => $dir, pid => 44444) ;

ok(connect_to($again->path), 'a new socket replaces it and works') ;

$again->close ;

# the default directory

{
local $ENV{HOME} = "$home" ;

my $default = KeyFilter::Control->new() ;

is($default->path, "$home/.config/keyfilter/sockets/$$.sock", 'without a directory the socket goes in the socket directory of the user') ;
ok(-S $default->path, 'and exists') ;

$default->close ;
}

# directories that already exist are left alone

my $existing = "$home/existing" ;

mkdir $existing, 0755 or die ;

my $kept = KeyFilter::Control->new(dir => $existing) ;

is(mode_of($existing), 0755, 'an existing directory keeps its permissions') ;

$kept->close ;

# errors

write_file("$home/file", "x\n") ;

like(failure_of(sub { KeyFilter::Control->new(dir => "$home/file/sockets") ; }), qr/\Acannot create the socket directory '\Q$home\E\/file\/sockets': /, 'a directory that cannot be created is fatal') ;

my $long = "$home/" . ('d' x 120) ;

like(failure_of(sub { KeyFilter::Control->new(dir => $long) ; }), qr/\Athe socket path '.*' is too long/, 'a path too long for a socket is fatal') ;
ok(!-e $long, 'and nothing is created') ;

SKIP:
	{
	skip 'permissions do not apply to this user', 1 if $> == 0 ;
	
	mkdir "$home/readonly", 0500 or die ;
	
	like(failure_of(sub { KeyFilter::Control->new(dir => "$home/readonly") ; }), qr/\Acannot create the socket '.*': Permission denied/, 'a directory that cannot be written is fatal') ;
	}

# descriptors

SKIP:
	{
	skip 'no /proc', 3 unless -d '/proc/self/fd' ;
	
	my $before = fd_count() ;
	my $holder = KeyFilter::Control->new(dir => $dir, pid => 55555) ;
	
	is(fd_count(), $before + 1, 'a control holds one descriptor') ;
	
	my $program = 'opendir(my $d, "/proc/self/fd") or die ; print join(" ", sort { $a <=> $b } grep { /^\d+$/ && $_ != fileno($d) } readdir $d), "\n"' ;
	
	is(run_engine({}, $^X, '-e', $program)->{output}, "0 1 2\r\n", 'which a command run by keyfilter does not inherit') ;
	
	$holder->close ;
	
	is(fd_count(), $before, 'and releases when closed') ;
	}

done_testing ;
