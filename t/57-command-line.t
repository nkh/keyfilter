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
my $counter = 0 ;

sub sq { my ($text) = @_ ; $text =~ s/'/'\\''/g ; return "'$text'" ; }

# -----------------------------------------------------------------------------

# run keyfilter with a child that collects N bytes in raw mode, typing INPUT after a pause

sub typed
{
my ($input, $bytes, @options) = @_ ;

return keyfilter_with($input, \@options, 'sh', '-c', "stty raw -echo ; head -c $bytes") ;
}

# -----------------------------------------------------------------------------

sub keyfilter_with
{
my ($input, $options, @command) = @_ ;

my $name = 'run' . ++$counter ;

write_file("$dir/$name.in", $input) ;

my $line = "(sleep 0.5 ; cat " . sq("$dir/$name.in") . ") | HOME=" . sq("$home") . " $^X " . sq($script) . ' ' . join(' ', map { sq($_) } @$options) . ' -- ' . join(' ', map { sq($_) } @command) . " 2>" . sq("$dir/$name.err") ;
my $out  = qx{$line} ;

return { output => $out, code => $? >> 8, error => read_file("$dir/$name.err") } ;
}

# -----------------------------------------------------------------------------

sub plain
{
my (@arguments) = @_ ;

my $name = 'plain' . ++$counter ;
my $line = "HOME=" . sq("$home") . " $^X " . sq($script) . ' ' . join(' ', map { sq($_) } @arguments) . " 2>" . sq("$dir/$name.err") . ' </dev/null' ;
my $out  = qx{$line} ;

return { output => $out, code => $? >> 8, error => read_file("$dir/$name.err") } ;
}

# -----------------------------------------------------------------------------

# the examples of the README

my $run = typed("\e[15~", 11, '--map', "F5=git status\\n") ;

is($run->{output}, "git status\n", "keyfilter --map F5='git status\\n' -- bash") ;
is($run->{code}, 0, 'ends well') ;
is($run->{error}, '', 'without a message') ;

is(typed("a\x1ab", 2, '--block', 'C-z')->{output}, 'ab', 'keyfilter --block C-z -- bash') ;
is(typed("\eb", 1, '--map', 'M-b=<<C-t>>')->{output}, "\x14", 'keyfilter --map M-b=<<C-t>> -- bash') ;

# rules

is(typed("a\x1a\x03b", 2, '--block', 'C-z', '--block', 'C-c')->{output}, 'ab', 'several --block') ;
is(typed("xaybz", 3, '--block', 'a b')->{output}, 'xyz', 'one --block with several keys') ;
is(typed("a", 1, '--block', 'a', '--unblock', 'a')->{output}, 'a', 'an --unblock after a --block lets the key through') ;
is(typed("ab", 1, '--unblock', 'a', '--block', 'a')->{output}, 'b', 'a --block after an --unblock blocks it') ;
is(typed("a", 1, '--map', 'a=1', '--map', 'a=2')->{output}, '2', 'the last --map of a key wins') ;
is(typed("ab", 2, '--map', 'a=b', '--map', 'b=c')->{output}, 'bc', 'maps do not chain') ;
is(typed("a", 1, '--map=a=z')->{output}, 'z', 'an option can have its value after an equal sign') ;
is(typed("a", 3, '--map', 'a=<<Up>>')->{output}, "\e[A", 'a key symbol in a map') ;
is(typed("a", 4, '--map', 'a=x\ty\n')->{output}, "x\ty\n", 'escapes in a map') ;
is(typed("a", 1, '--map', 'a=\#')->{output}, '#', 'a hash in a map is written \#') ;
is(typed("\e[A\e[B", 3, '--block', 'Up')->{output}, "\e[B", 'a key that is a sequence is blocked') ;
is(typed("a", 1, '--block', 'b')->{output}, 'a', 'other keys pass') ;
is(typed("abc", 3)->{output}, 'abc', 'without options nothing is changed') ;

# profiles

mkdir "$home/.config" ; mkdir "$home/.config/keyfilter" ;

write_file("$home/.config/keyfilter/vim.profile", "map a=v\n", "block x\n") ;
write_file("$home/.config/keyfilter/common.profile", "map a=c\n", "map b=c\n") ;
write_file("$dir/local.profile", "map a=l\n") ;

is(typed("axb", 2, '--profile', 'vim')->{output}, 'vb', 'keyfilter --profile vim -- vim') ;
is(typed("ab", 2, '--profile', 'common', '--profile', 'vim')->{output}, 'vc', 'several profiles, a later one wins') ;
is(typed("ab", 2, '--profile', 'vim', '--profile', 'common')->{output}, 'cc', 'in the order given') ;
is(typed("a", 1, '--profile', "$dir/local.profile")->{output}, 'l', 'a profile can be a path') ;
is(typed("ab", 2, '--profile', 'vim', '--map', 'a=z')->{output}, 'zb', 'the command line overrides the profiles') ;
is(typed("ab", 2, '--map', 'a=z', '--profile', 'vim')->{output}, 'zb', 'wherever the profile is on the command line') ;

write_file("$home/.config/keyfilter/with-include.profile", "include included.profile\n", "map d=4\n") ;
write_file("$home/.config/keyfilter/included.profile", "map c=3\n") ;

is(typed("cd", 2, '--profile', 'with-include')->{output}, '34', 'a profile can include another') ;

# startup

$run = keyfilter_with('', ['--startup-delay', '300', '--send-startup', 'source env.sh\n'], 'sh', '-c', 'read x ; echo got:$x') ;

like($run->{output}, qr/got:source env\.sh\r\n/, "keyfilter --startup-delay 500 --send-startup 'source env.sh\\n' -- bash") ;
is($run->{code}, 0, 'ends well') ;

$run = keyfilter_with('', ['--startup-delay', '300', '--send-startup', 'one', '--send-startup', 'two'], 'sh', '-c', 'stty raw -echo ; head -c 6') ;

is($run->{output}, 'onetwo', 'several --send-startup, in order') ;

$run = keyfilter_with('', ['--startup-delay', '300', '--send-startup', 'late'], 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 4') ;

is($run->{output}, "ready\nlate", 'the startup text comes after the delay') ;

write_file("$home/.config/keyfilter/starting.profile", "send-startup from profile\n", "startup-delay 100\n") ;


$run = keyfilter_with('', ['--profile', 'starting', '--send-startup', '\x20and line'], 'sh', '-c', 'stty raw -echo ; head -c 21') ;

is($run->{output}, 'from profile and line', 'startup of a profile comes before the startup of the command line') ;

# recording

my $recorded = "$dir/cli.rec" ;

typed("a\x1ab", 2, '--record', $recorded, '--block', 'C-z') ;

my @events = KeyFilter::Recorder::parse_recording(read_file($recorded)) ;


like(join('', map { $_->{data} } grep { $_->{type} eq 'I' } @events), qr/\Aab/, 'a recording has what the child received, not what was typed') ;
is(KeyFilter::Recorder::exit_code_of(@events), 0, 'and the exit code') ;

# errors

for my $case (
	[['--map', 'F5', '--', 'true'], qr/\Akeyfilter: option '--map': invalid syntax, expected: map KEY=REPLACEMENT\n\z/],
	[['--block', 'bogus', '--', 'true'], qr/\Akeyfilter: option '--block': unknown key specification 'bogus'\n\z/],
	[['--unblock', '', '--', 'true'], qr/\Akeyfilter: option '--unblock': unblock requires at least one key specification\n\z/],
	[['--map', 'a=\q', '--', 'true'], qr/\Akeyfilter: option '--map': unknown escape/],
	[['--startup-delay', '5s', '--', 'true'], qr/\Akeyfilter: option '--startup-delay': invalid duration '5s'/],
	[['--send-startup', '', '--', 'true'], qr/\Akeyfilter: option '--send-startup': send-startup requires text\n\z/],
	[['--block'], qr/\Akeyfilter: option '--block' needs a value\n\z/],
	[['--map'], qr/\Akeyfilter: option '--map' needs a value\n\z/],
	[['--profile'], qr/\Akeyfilter: option '--profile' needs a value\n\z/],
	[['--profile='], qr/\Akeyfilter: option '--profile' needs a value\n\z/],
	[['--send-startup', "a\nb", '--', 'true'], qr/\Akeyfilter: option '--send-startup': the value cannot contain a line end, write \\n\n\z/],
	[['--map', "a=b\r", '--', 'true'], qr/\Akeyfilter: option '--map': the value cannot contain a line end/],
	[['--bogus'], qr/\Akeyfilter: unknown option '--bogus'\n\z/],
	[['--no-socket=1'], qr/\Akeyfilter: option '--no-socket' takes no value\n\z/],
	)
	{
	my ($arguments, $pattern) = @$case ;
	
	my $failed = plain(@$arguments) ;
	
	like($failed->{error}, $pattern, "refused: @$arguments") ;
	is($failed->{code}, 1, 'with a usage code') ;
	is($failed->{output}, '', 'and no output') ;
	}

my $missing = plain('--profile', 'nope', '--', 'true') ;

like($missing->{error}, qr/\Akeyfilter: missing profile 'nope', looked for '\Q$home\E\/\.config\/keyfilter\/nope\.profile'\n\z/, 'a profile that does not exist is a fatal error') ;
is($missing->{code}, 255, 'with a failure code') ;

write_file("$home/.config/keyfilter/broken.profile", "block a\n", "bogus\n") ;

like(plain('--profile', 'broken', '--', 'true')->{error}, qr/\Akeyfilter: \Q$home\E\/\.config\/keyfilter\/broken\.profile:2: unknown command 'bogus'\n\z/, 'a profile with an error names the file and the line') ;
like(plain('--map', 'a=b')->{error}, qr/\AUsage: keyfilter \[options\] -- command \[args\.\.\.\]\nTry 'keyfilter --help'/, 'options without a command give the usage') ;
is(plain('--map', 'a=b')->{code}, 1, 'and a usage code') ;
like(plain('--replay', 'x', '--block', 'a')->{error}, qr/--replay cannot be used with rules, profiles or startup options/, 'replay does not take rules') ;
like(plain('--replay', 'x', '--profile', 'a')->{error}, qr/--replay cannot be used with rules/, 'nor profiles') ;
like(plain('--discover', '--block', 'a')->{error}, qr/--discover cannot be used with other options/, 'nor does discover') ;

# the command is not mistaken for an option


is(plain('sh', '-c', 'echo "$1"', 'sh', '--help')->{output}, "--help\r\n", 'after the command everything is for the command') ;
is(plain('--', '--version')->{error}, "keyfilter: cannot execute '--version': No such file or directory\n", 'after the double dash too') ;

# help and version

my $help = plain('--help') ;

is($help->{code}, 0, '--help succeeds') ;
is($help->{error}, '', 'and writes nothing on the error output') ;
is($help->{output}, KeyFilter::CLI::help_text(), 'it shows the help') ;
is(plain('-h')->{output}, $help->{output}, '-h is the same') ;
is(plain('--help', '--bogus')->{output}, $help->{output}, 'help is given before options are checked') ;
is(plain('--block', 'a', '-h', '--', 'true')->{output}, $help->{output}, 'wherever it is among the options') ;

for my $option ('--block', '--unblock', '--map', '--profile', '--startup-delay', '--send-startup', '--record', '--replay', '--fast', '--discover', '--no-socket', '--help', '--version', '-h')
	{
	like($help->{output}, qr/\Q$option\E/, "the help tells about $option") ;
	}

like($help->{output}, qr/\AUsage: keyfilter \[options\] \[--\] command/, 'the help starts with the usage') ;
like($help->{output}, qr/keyfilter --map F5='git status\\n' -- bash/, 'and has the examples of the README') ;
like($help->{output}, qr/keyfilterctl/, 'and mentions keyfilterctl') ;

my $version = plain('--version') ;

is($version->{output}, "keyfilter $KeyFilter::CLI::VERSION\n", '--version shows the version') ;
is($version->{code}, 0, 'and succeeds') ;

# the control socket

my $socket_home = temp_dir() ;
my $sockets     = "$socket_home/.config/keyfilter/sockets" ;
my $pid         = fork() ;

if ($pid == 0)
	{
	$ENV{HOME} = "$socket_home" ;
	
	open(STDIN, '<', '/dev/null') ;
	open(STDOUT, '>', '/dev/null') ;
	open(STDERR, '>', '/dev/null') ;
	
	exec $^X, $script, '--profile', "$dir/local.profile", '--', 'sleep', '1.5' ;
	}

my $deadline = Time::HiRes::time() + 10 ;

Time::HiRes::sleep(0.05) until (-d $sockets && glob("$sockets/*.sock")) || Time::HiRes::time() > $deadline ;

my @instances = KeyFilter::Control::instances($sockets) ;

is(scalar @instances, 1, 'a running instance has a control socket') ;
is($instances[0]{pid}, $pid, 'named after its pid') ;
is($instances[0]{info}{command}, 'sleep 1.5', 'with the command it runs') ;
is($instances[0]{info}{profiles}, 'local', 'and the profiles it has') ;
like($instances[0]{info}{started}, qr/\A\d+\z/, 'and when it started') ;

waitpid($pid, 0) ;

is_deeply([ glob("$sockets/*") ], [], 'the socket and its information are removed when it ends') ;

my $no_socket_home = temp_dir() ;

$pid = fork() ;

if ($pid == 0)
	{
	$ENV{HOME} = "$no_socket_home" ;
	
	open(STDIN, '<', '/dev/null') ;
	open(STDOUT, '>', '/dev/null') ;
	
	exec $^X, $script, '--no-socket', '--', 'sleep', '1' ;
	}

Time::HiRes::sleep(0.5) ;

ok(!-e "$no_socket_home/.config", '--no-socket creates nothing') ;

waitpid($pid, 0) ;

my $blocked_home = "$dir/blocked-home" ;

write_file($blocked_home, "a file where a directory is needed\n") ;

my $without_line = 'HOME=' . sq($blocked_home) . " $^X " . sq($script) . q{ -- sh -c 'echo still works ; exit 3' 2>&1 </dev/null} ;
my $without      = qx{$without_line} ;

like($without, qr/\Akeyfilter: no control socket: cannot create the socket directory '.*': /, 'when the socket cannot be created keyfilter says so') ;
like($without, qr/still works\r\n/, 'and runs the command anyway') ;
is($? >> 8, 3, 'with its exit code') ;

# the table of options

is_deeply(KeyFilter::CLI::parse_arguments('--block', 'C-z', '--map', 'a=b', '--unblock', 'q', '--', 'bash'), { command => ['bash'], commands => [ map { scalar KeyFilter::Command::parse_command($_) } 'block C-z', 'map a=b', 'unblock q' ] }, 'rule options keep the order they were given in') ;
is_deeply(KeyFilter::CLI::parse_arguments('--profile', 'a', '--profile', 'b', 'cmd'), { command => ['cmd'], profiles => ['a', 'b'] }, 'profiles are listed in order') ;
is_deeply(KeyFilter::CLI::parse_arguments('--startup-delay', '5', '--send-startup', 'x', 'cmd'), { command => ['cmd'], commands => [ map { scalar KeyFilter::Command::parse_command($_) } 'startup-delay 5', 'send-startup x' ] }, 'startup options are commands too') ;
is_deeply(KeyFilter::CLI::parse_arguments('--no-socket', 'cmd'), { command => ['cmd'], no_socket => 1 }, '--no-socket') ;
is_deeply(KeyFilter::CLI::parse_arguments('-h'), { command => [], help => 1 }, '-h') ;
is_deeply(KeyFilter::CLI::parse_arguments('--help'), { command => [], help => 1 }, '--help') ;
is_deeply(KeyFilter::CLI::parse_arguments('--version'), { command => [], version => 1 }, '--version') ;
is_deeply(KeyFilter::CLI::parse_arguments('--record', 'f', '--block', 'a', 'cmd'), { command => ['cmd'], record => 'f', commands => [ scalar KeyFilter::Command::parse_command('block a') ] }, 'options can be mixed') ;

done_testing ;
