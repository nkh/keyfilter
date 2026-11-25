#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use IO::Select () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $home    = temp_dir() ;
my $control = KeyFilter::Control->new(dir => "$home/sockets") ;

sub client { return IO::Socket::UNIX->new(Peer => $control->path, Type => Socket::SOCK_STREAM()) ; }

# -----------------------------------------------------------------------------

sub drain
{
my ($quiet) = @_ ;

$quiet //= 0.15 ;

my @commands ;
my $last = Time::HiRes::time() ;

while (Time::HiRes::time() - $last < $quiet)
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

sub names { return map { $_->{cmd} } @_ ; }

# -----------------------------------------------------------------------------

# the language of the socket

my @accepted =
	(
	['block C-z', { cmd => 'block', keys => ["\x1a"] }],
	['block a b Up', { cmd => 'block', keys => ['a', 'b', "\e[A"] }],
	['unblock C-z', { cmd => 'unblock', keys => ["\x1a"] }],
	['map F1=<<Enter>>', { cmd => 'map', key => "\eOP", replacement => "\r" }],
	['map a=git status\n', { cmd => 'map', key => 'a', replacement => "git status\n" }],
	['toggle gaming', { cmd => 'toggle', profile => 'gaming' }],
	['send abc<<Enter>>', { cmd => 'send', text => "abc\r" }],
	['send hello world ', { cmd => 'send', text => 'hello world ' }],
	['  block   a  # no a', { cmd => 'block', keys => ['a'] }],
	['block a', { cmd => 'block', keys => ['a'] }],
	) ;

for my $case (@accepted)
	{
	my ($line, $expected) = @$case ;
	
	is_deeply(KeyFilter::Control::parse_line($line), $expected, "accepted: $line") ;
	}

is_deeply(KeyFilter::Control::parse_line("block a\r"), { cmd => 'block', keys => ['a'] }, 'a carriage return at the end of a line is ignored') ;

for my $line ('', '   ', '# comment', '   # comment', '#')
	{
	is(KeyFilter::Control::parse_line($line), undef, "no command in '$line'") ;
	}

my @refused =
	(
	['startup-delay 500', qr/\Athe command 'startup-delay' is not allowed at runtime/],
	['send-startup make\n', qr/\Athe command 'send-startup' is not allowed at runtime/],
	['include common.profile', qr/\Athe command 'include' is not allowed at runtime/],
	['profile vim', qr/\Athe command 'profile' is not allowed at runtime/],
	['frobnicate x', qr/\Aunknown command 'frobnicate'/],
	['block', qr/\Ablock requires at least one key specification/],
	['block bogus', qr/\Aunknown key specification 'bogus'/],
	['unblock', qr/\Aunblock requires/],
	['map a', qr/\Ainvalid syntax/],
	['map bogus=x', qr/\Aunknown key specification 'bogus'/],
	['map a=<<bogus>>', qr/\Aunknown key specification 'bogus'/],
	['toggle', qr/\Atoggle requires an argument/],
	['send', qr/\Asend requires text/],
	['send a\q', qr/\Aunknown escape/],
	['Block a', qr/\Aunknown command 'Block'/],
	) ;

for my $case (@refused)
	{
	my ($line, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Control::parse_line($line) ; }), $pattern, "refused: $line") ;
	}

# lines from a client

is_deeply([ $control->errors ], [], 'there is no error at the start') ;
is($control->client_count, 0, 'and no client') ;
is_deeply([ $control->handles ], [ $control->listener ], 'only the listening socket is waited for') ;

my $one = client() ;

syswrite($one, "block C-z\nmap a=b\nsend hi\n") ;

my @commands = drain() ;

is_deeply([ names(@commands) ], ['block', 'map', 'send'], 'the lines of a client are commands, in order') ;
is($commands[1]{replacement}, 'b', 'with their arguments') ;
is($control->client_count, 1, 'the client is kept while it is connected') ;
is(scalar(() = $control->handles), 2, 'and waited for') ;

# lines that arrive in pieces

syswrite($one, 'block ') ;

is_deeply([ drain(0.1) ], [], 'a line that is not finished gives no command') ;

syswrite($one, "C-c") ;

is_deeply([ drain(0.1) ], [], 'nor does the next piece') ;

syswrite($one, "\n") ;

@commands = drain(0.1) ;

is_deeply(\@commands, [{ cmd => 'block', keys => ["\x03"] }], 'the line is a command when its end arrives') ;

for my $byte (split //, "unblock a\n")
	{
	syswrite($one, $byte) ;
	
	Time::HiRes::sleep(0.01) ;
	}

is_deeply([ names(drain()) ], ['unblock'], 'a line written one byte at a time is one command') ;

syswrite($one, "block a\nblock b\nbloc") ;

@commands = drain() ;

is(scalar @commands, 2, 'two lines and the start of a third give two commands') ;

syswrite($one, "k c\n") ;

@commands = drain() ;

is_deeply([ map { $_->{keys}[0] } @commands ], ['c'], 'and the third when it is finished') ;

syswrite($one, "block a\r\nblock b\r\n") ;

is(scalar(() = drain()), 2, 'lines that end with carriage return and newline') ;

syswrite($one, "\n\n# comment\n   \nblock x\n\n") ;

@commands = drain() ;

is(scalar @commands, 1, 'blank lines and comments are no commands') ;
is_deeply([ $control->errors ], [], 'and no errors') ;

syswrite($one, join('', map { "block a$_\n" } ()) . join('', map { "send line$_\n" } 1 .. 1000)) ;

@commands = drain(0.3) ;

is(scalar @commands, 1000, 'a thousand lines in one write are a thousand commands') ;
is_deeply([ map { $_->{text} } @commands ], [ map { "line$_" } 1 .. 1000 ], 'in order') ;

# lines that are wrong

syswrite($one, "block a\nfrobnicate\nblock b\nstartup-delay 5\nmap x\nblock c\n") ;

@commands = drain() ;

is_deeply([ map { $_->{keys}[0] } @commands ], ['a', 'b', 'c'], 'the lines that are right are commands, whatever surrounds them') ;

my @errors = $control->errors ;

is_deeply([ map { $_->{line} } @errors ], ['frobnicate', 'startup-delay 5', 'map x'], 'the lines that are wrong are kept') ;
like($errors[0]{error}, qr/\Aunknown command 'frobnicate'\z/, 'with what is wrong') ;
like($errors[1]{error}, qr/\Athe command 'startup-delay' is not allowed at runtime\z/, 'a command that is not for the runtime') ;
like($errors[2]{error}, qr/\Ainvalid syntax/, 'a syntax error') ;
is($control->client_count, 1, 'and the client stays connected') ;

$control->clear_errors ;

is_deeply([ $control->errors ], [], 'errors can be cleared') ;

$errors[0]{line} = 'changed' ;

syswrite($one, "nope\n") ;

drain() ;

is(($control->errors)[0]{line}, 'nope', 'errors given out are copies') ;

$control->clear_errors ;

syswrite($one, "\x00\x01\xff garbage \xfe\n" . "block a\n") ;

@commands = drain() ;

is(scalar @commands, 1, 'binary garbage on a line does not stop the next line') ;
is(scalar($control->errors), 1, 'it is an error') ;

$control->clear_errors ;

# ending

close $one ;

drain() ;

is($control->client_count, 0, 'a client that disconnects is forgotten') ;
is_deeply([ $control->handles ], [ $control->listener ], 'and is not waited for') ;

my $unfinished = client() ;

syswrite($unfinished, "block a\nsend last words") ;

close $unfinished ;

@commands = drain() ;

is_deeply([ names(@commands) ], ['block', 'send'], 'a last line without a newline is a command when the client ends') ;
is($commands[1]{text}, 'last words', 'with all its text') ;
is($control->client_count, 0, 'and the client is forgotten') ;

my $silent = client() ;

close $silent ;

is_deeply([ drain() ], [], 'a client that says nothing gives nothing') ;
is($control->client_count, 0, 'and is forgotten') ;
is_deeply([ $control->errors ], [], 'without an error') ;

my $bad_end = client() ;

syswrite($bad_end, "frobnicate") ;

close $bad_end ;

drain() ;

is(scalar($control->errors), 1, 'an unfinished line that is wrong is an error') ;

$control->clear_errors ;

# several clients

my $first  = client() ;
my $second = client() ;

drain() ;

is($control->client_count, 2, 'several clients can be connected') ;

syswrite($first, 'block ') ;
syswrite($second, 'send ') ;
drain(0.1) ;
syswrite($second, "second\n") ;
syswrite($first, "f\n") ;

@commands = drain() ;

is_deeply([ sort map { $_->{cmd} } @commands ], ['block', 'send'], 'pieces of lines of two clients are not mixed') ;

my ($block) = grep { $_->{cmd} eq 'block' } @commands ;
my ($send)  = grep { $_->{cmd} eq 'send' } @commands ;

is_deeply([ $block->{keys}, $send->{text} ], [['f'], 'second'], 'each line is the line of its client') ;

close $first ;

drain() ;

is($control->client_count, 1, 'one client is gone, the other stays') ;

syswrite($second, "block z\n") ;

is_deeply([ names(drain()) ], ['block'], 'and still works') ;

close $second ;

drain() ;

# too much

my $greedy = client() ;
my $other  = client() ;

syswrite($greedy, "block a\n") ;
drain() ;

my $limit = Time::HiRes::time() + 10 ;
my $sent  = 0 ;

$greedy->blocking(0) ;

while ($control->client_count == 2 && Time::HiRes::time() < $limit)
	{
	my $written = syswrite($greedy, 'x' x 4096) ;
	
	$sent += $written if defined $written ;
	
	drain(0.01) ;
	}

is($control->client_count, 1, 'a client that sends a line that never ends is dropped') ;
cmp_ok($sent, '>', 65536, 'after too many bytes') ;
cmp_ok($sent, '<', 200000, 'but not many more') ;
is_deeply([ map { $_->{error} } $control->errors ], ['line too long'], 'which is an error') ;

syswrite($other, "block b\n") ;

is_deeply([ names(drain()) ], ['block'], 'the other clients are not affected') ;

$control->clear_errors ;

my $long = client() ;

syswrite($long, 'send ' . ('a' x 60000) . "\n") ;

@commands = drain(0.3) ;

is(length $commands[0]{text}, 60000, 'a long line below the limit is a command') ;

# the end

is_deeply([ $control->service(undef) ], [], 'servicing nothing gives nothing') ;
is_deeply([ $control->service(\*STDIN) ], [], 'and servicing something unknown too') ;

$control->close ;

is_deeply([ $control->handles ], [], 'a closed control waits for nothing') ;
is($control->client_count, 0, 'and has no clients') ;
is_deeply([ $control->service($other) ], [], 'and services nothing') ;

done_testing ;
