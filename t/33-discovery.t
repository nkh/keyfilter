#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use POSIX () ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub keys_of { my ($buffer) = @_ ; my ($keys, $rest) = KeyFilter::Key::split_keys($buffer) ; return ($keys, $rest) ; }

# -----------------------------------------------------------------------------

sub hex_list { return join('|', map { unpack('H*', $_) } @_) ; }

# -----------------------------------------------------------------------------

sub discover
{
my ($data, %arguments) = @_ ;

my $dir = temp_dir() ;

write_file("$dir/input", $data) ;

open(my $input, '<', "$dir/input") or die ;
open(my $output, '>', "$dir/output") or die ;
open(my $error, '>', "$dir/error") or die ;

my $code = KeyFilter::Discovery::run(input => $input, output => $output, error => $error, %arguments) ;

close $output ;
close $error ;

return { code => $code, output => read_file("$dir/output"), error => read_file("$dir/error") } ;
}

# -----------------------------------------------------------------------------

sub record
{
my ($name, $sequence) = @_ ;

return "Key      : $name\nSequence : $sequence\n\n" ;
}

# -----------------------------------------------------------------------------

# splitting a stream of bytes into keys

my @splits =
	(
	['', [], ''],
	['abc', ['a', 'b', 'c'], ''],
	["\e[A", ["\e[A"], ''],
	["\e[1;5A", ["\e[1;5A"], ''],
	["\e[15;8~", ["\e[15;8~"], ''],
	["\eOP", ["\eOP"], ''],
	["\ea", ["\ea"], ''],
	["\e\r", ["\e\r"], ''],
	["\e\x7f", ["\e\x7f"], ''],
	["\e\x01", ["\e\x01"], ''],
	["\e\e[A", ["\e\e[A"], ''],
	["\e\eOP", ["\e\eOP"], ''],
	["\e\ea", ["\e\e", 'a'], ''],
	["\e", [], "\e"],
	["\e[", [], "\e["],
	["\e[1;", [], "\e[1;"],
	["\e[1;5", [], "\e[1;5"],
	["\eO", [], "\eO"],
	["\e\e", [], "\e\e"],
	["\e\e[", [], "\e\e["],
	["\e\e[1", [], "\e\e[1"],
	["a\e[Ab", ['a', "\e[A", 'b'], ''],
	["a\e", ['a'], "\e"],
	["\e[A\e[B", ["\e[A", "\e[B"], ''],
	["\e[A\e", ["\e[A"], "\e"],
	["\x01\x1a", ["\x01", "\x1a"], ''],
	["\x00", ["\x00"], ''],
	["\xc3\xa9", ["\xc3\xa9"], ''],
	["\xe2\x82\xac", ["\xe2\x82\xac"], ''],
	["\xf0\x9f\x98\x80", ["\xf0\x9f\x98\x80"], ''],
	["\xc3", [], "\xc3"],
	["\xe2\x82", [], "\xe2\x82"],
	["\xf0\x9f\x98", [], "\xf0\x9f\x98"],
	["\xc3a", ["\xc3", 'a'], ''],
	["\xe2\x82a", ["\xe2", "\x82", 'a'], ''],
	["\xff", ["\xff"], ''],
	["\x80", ["\x80"], ''],
	["\xc0\x80", ["\xc0", "\x80"], ''],
	["\e\xc3\xa9", ["\e\xc3\xa9"], ''],
	["\e\xc3", [], "\e\xc3"],
	["\e[<0;10;20M", ["\e[<0;10;20M"], ''],
	["\e[200~", ["\e[200~"], ''],
	["\e[?1;2c", ["\e[?1;2c"], ''],
	["\e[ q", ["\e[ q"], ''],
	["\e[1;5;;A", ["\e[1;5;;A"], ''],
	["\e[\x01", ["\e", '[', "\x01"], ''],
	["\e[1\x01", ["\e", '[', '1', "\x01"], ''],
	["x\e[1;2Ay\eOQz", ['x', "\e[1;2A", 'y', "\eOQ", 'z'], ''],
	) ;

for my $case (@splits)
	{
	my ($input, $keys, $rest) = @$case ;
	
	my ($got_keys, $got_rest) = keys_of($input) ;
	
	is_deeply([$got_keys, $got_rest], [$keys, $rest], 'split ' . unpack('H*', $input)) ;
	}

is_deeply([ KeyFilter::Key::flush_keys('') ], [], 'flushing nothing gives no key') ;
is_deeply([ KeyFilter::Key::flush_keys("\e[1;") ], ["\e[1;"], 'flushing an unfinished sequence gives one key') ;
is_deeply([ KeyFilter::Key::flush_keys("\e") ], ["\e"], 'a lone escape is a key') ;

# splitting never loses or invents a byte, whatever the bytes are

srand(2026) ;

my @alphabet = ("\e", '[', 'O', ';', '1', '5', 'A', '~', 'a', ' ', "\x01", "\x7f", "\xc3", "\xa9", "\xe2", "\x82", "\xff", "\x00", '<', 'M', "\x03") ;
my $bad      = 0 ;
my $unstable = 0 ;
my $consist  = 0 ;
my $empty    = 0 ;

for (1 .. 1500)
	{
	my $input = join('', map { $alphabet[int rand @alphabet] } 1 .. int(rand 14)) ;
	
	my ($keys, $rest) = keys_of($input) ;
	
	$bad++ unless join('', @$keys) . $rest eq $input ;
	$empty++ if grep { !length } @$keys ;
	
	my ($again, $again_rest) = keys_of($rest) ;
	
	$unstable++ unless !@$again && $again_rest eq $rest ;
	
	my @whole = (@$keys, KeyFilter::Key::flush_keys($rest)) ;
	
	for my $cut (0 .. length $input)
		{
		my ($first, $first_rest)   = keys_of(substr($input, 0, $cut)) ;
		my ($second, $second_rest) = keys_of($first_rest . substr($input, $cut)) ;
		
		my @streamed = (@$first, @$second, KeyFilter::Key::flush_keys($second_rest)) ;
		
		$consist++ unless hex_list(@streamed) eq hex_list(@whole) ;
		}
	}

is($bad, 0, 'the keys and the remainder always make the input again') ;
is($empty, 0, 'a key is never empty') ;
is($unstable, 0, 'a remainder alone gives no key') ;
is($consist, 0, 'cutting the input anywhere gives the same keys') ;

# names of keys

my %names =
	(
	'a'          => 'a',
	'Z'          => 'Z',
	'1'          => '1',
	'~'          => '~',
	'#'          => '\#',
	'\\'         => '\\',
	' '          => 'Space',
	"\r"         => 'Enter',
	"\t"         => 'Tab',
	"\e"         => 'Esc',
	"\x7f"       => 'Backspace',
	"\x00"       => 'C-Space',
	"\x01"       => 'C-a',
	"\x1a"       => 'C-z',
	"\x08"       => 'C-h',
	"\x1c"       => 'C-\\',
	"\x1d"       => 'C-]',
	"\x1e"       => 'C-^',
	"\x1f"       => 'C-_',
	"\e[A"       => 'Up',
	"\e[B"       => 'Down',
	"\e[C"       => 'Right',
	"\e[D"       => 'Left',
	"\e[H"       => 'Home',
	"\e[F"       => 'End',
	"\e[2~"      => 'Insert',
	"\e[3~"      => 'Delete',
	"\e[5~"      => 'PgUp',
	"\e[6~"      => 'PgDn',
	"\e[1;2A"    => 'S-Up',
	"\e[1;3A"    => 'M-Up',
	"\e[1;5A"    => 'C-Up',
	"\e[1;4A"    => 'M-S-Up',
	"\e[1;6A"    => 'C-S-Up',
	"\e[1;7A"    => 'C-M-Up',
	"\e[1;8A"    => 'C-M-S-Up',
	"\eOP"       => 'F1',
	"\eOS"       => 'F4',
	"\e[1;5S"    => 'C-F4',
	"\e[15~"     => 'F5',
	"\e[24~"     => 'F12',
	"\e[15;8~"   => 'C-M-S-F5',
	"\e[3;5~"    => 'C-Delete',
	"\e[Z"       => 'S-Tab',
	"\e\e[Z"     => 'M-S-Tab',
	"\ea"        => 'M-a',
	"\eA"        => 'M-A',
	"\e#"        => 'M-\#',
	"\e\r"       => 'M-Enter',
	"\e\t"       => 'M-Tab',
	"\e\e"       => 'M-Esc',
	"\e "        => 'M-Space',
	"\e\x7f"     => 'M-Backspace',
	"\e\x01"     => 'C-M-a',
	"\e\x00"     => 'C-M-Space',
	"\e["        => 'M-[',
	"\eO"        => 'M-O',
	) ;

for my $sequence (sort keys %names)
	{
	is(KeyFilter::Key::name_of($sequence), $names{$sequence}, 'name of ' . unpack('H*', $sequence)) ;
	}

my @unknown = ('', "\e[99~", "\e[1;9A", "\xc3\xa9", "\xff", "\x80", "\e[1;5", "\eOZ", "ab", "\e[A\e[A", "\e\e\e") ;

is(KeyFilter::Key::name_of($_), undef, 'no name for ' . unpack('H*', $_)) for @unknown ;

is_deeply([ grep { !defined KeyFilter::Key::name_of(chr $_) } 0 .. 127 ], [], 'every ascii byte has a name') ;
is_deeply([ grep { defined KeyFilter::Key::name_of(chr $_) } 128 .. 255 ], [], 'and no other byte has one') ;

my $unparsable = 0 ;
my $unnamed    = 0 ;
my $mismatch   = 0 ;

for my $spec (KeyFilter::Key::candidate_specs())
	{
	my $sequence = eval { KeyFilter::Key::parse_key($spec) ; } ;
	
	if (!defined $sequence)
		{
		$unparsable++ ;
		
		next ;
		}
	
	my $name = KeyFilter::Key::name_of($sequence) ;
	
	if (!defined $name)
		{
		$unnamed++ ;
		
		next ;
		}
	
	$mismatch++ unless KeyFilter::Key::parse_key($name) eq $sequence ;
	}

is($unparsable, 0, 'every key the names are made from can be parsed') ;
is($unnamed, 0, 'and has a name') ;
is($mismatch, 0, 'a name parses back to the bytes it was found for') ;
cmp_ok(scalar(KeyFilter::Key::candidate_specs()), '>', 300, 'many keys have a name') ;

# what discovery prints

is(KeyFilter::Discovery::describe("\e[A"), record('Up', '1b 5b 41'), 'a key is described by its name and its bytes') ;
is(KeyFilter::Discovery::describe('a'), record('a', '61'), 'a letter') ;
is(KeyFilter::Discovery::describe("\x00"), record('C-Space', '00'), 'a zero byte is shown as two digits') ;
is(KeyFilter::Discovery::describe("\e[1;5A"), record('C-Up', '1b 5b 31 3b 35 41'), 'a long sequence') ;
is(KeyFilter::Discovery::describe("\xc3\xa9"), record('(unknown)', 'c3 a9'), 'a key without a name is unknown') ;
is(KeyFilter::Discovery::describe("\e[99~"), record('(unknown)', '1b 5b 39 39 7e'), 'so is an unknown sequence') ;
is(KeyFilter::Discovery::describe('a', "\r\n"), "Key      : a\r\nSequence : 61\r\n\r\n", 'the line end can be chosen') ;
is(KeyFilter::Discovery::hex_of("\x0a\xff"), '0a ff', 'bytes are shown in lower case hexadecimal') ;
is(KeyFilter::Discovery::hex_of(''), '', 'no bytes, no digits') ;

# discovery on a stream

my $run = discover("a\e[A\x7f") ;

is($run->{output}, record('a', '61') . record('Up', '1b 5b 41') . record('Backspace', '7f'), 'each key is reported in turn') ;
is($run->{code}, 0, 'discovery ends with 0') ;
is($run->{error}, '', 'and says nothing on the error output when the input is not a terminal') ;

is(discover('')->{output}, '', 'no input, no report') ;
is(discover("\e")->{output}, record('Esc', '1b'), 'a lone escape at the end of the input is Esc') ;
is(discover("\e[1;")->{output}, record('(unknown)', '1b 5b 31 3b'), 'an unfinished sequence at the end of the input is reported as it is') ;
is(discover("\e[")->{output}, record('M-[', '1b 5b'), 'an escape and a bracket at the end of the input is Alt and bracket') ;
is(discover("\xc3\xa9")->{output}, record('(unknown)', 'c3 a9'), 'text outside ascii is unknown') ;
is(discover("\xc3")->{output}, record('(unknown)', 'c3'), 'half a character at the end is reported') ;
is(discover("\x03")->{output}, record('C-c', '03'), 'one Ctrl-C is a key like another') ;
is(discover("\x03a\x03b")->{output}, record('C-c', '03') . record('a', '61') . record('C-c', '03') . record('b', '62'), 'Ctrl-C twice in a row, with a key in between, does not stop') ;
is(discover("a\x03\x03b")->{output}, record('a', '61') . record('C-c', '03') . record('C-c', '03'), 'Ctrl-C twice in a row stops after the second') ;
is(discover("\x03\x03\x03")->{output}, record('C-c', '03') . record('C-c', '03'), 'and nothing is read after that') ;
is(discover("\x03\x03")->{code}, 0, 'with 0 too') ;

my $big = discover('a' x 10000) ;

is(scalar(() = $big->{output} =~ /^Key      : a$/mg), 10000, 'a long stream is reported key by key') ;

# a stream of known keys, in blocks larger than a read

my @allowed = grep { my $s = $_ ; !grep { $_ eq $s } ("\e", "\e[", "\eO", "\e\e", "\x03") } map { my $k = eval { KeyFilter::Key::parse_key($_) ; } ; defined $k ? $k : () } KeyFilter::Key::candidate_specs() ;

srand(11) ;

my @stream = map { $allowed[int rand @allowed] } 1 .. 3000 ;
my $result = discover(join('', @stream)) ;
my $expect = join('', map { KeyFilter::Discovery::describe($_) } @stream) ;

ok($result->{output} eq $expect, 'three thousand random keys are all found and named, across the reads') ;

my $unnamed_keys = grep { !defined KeyFilter::Key::name_of($_) } @stream ;

is($unnamed_keys, 0, 'and all of them have a name') ;

# pieces that arrive late

sub piped_discovery
{
my (%arguments) = @_ ;

my @close = @{ delete $arguments{close} // [] } ;

pipe(my $out_read, my $out_write) or die ;
pipe(my $err_read, my $err_write) or die ;

my $pid = fork() ;

die "fork: $!\n" unless defined $pid ;

if ($pid == 0)
	{
	close $out_read ;
	close $err_read ;
	close $_ for @close ;
	
	my $code = eval { KeyFilter::Discovery::run(%arguments, output => $out_write, error => $err_write) ; } ;
	
	POSIX::_exit(defined $code ? $code : 255) ;
	}

close $out_write ;
close $err_write ;

return { pid => $pid, output => $out_read, error => $err_read } ;
}

# -----------------------------------------------------------------------------

sub finish_discovery
{
my ($process) = @_ ;

my $deadline = Time::HiRes::time() + 10 ;

while (Time::HiRes::time() < $deadline)
	{
	my $done = waitpid($process->{pid}, POSIX::WNOHANG()) ;
	
	return $? >> 8 if $done == $process->{pid} ;
	
	Time::HiRes::sleep(0.02) ;
	}

kill 'KILL', $process->{pid} ;
waitpid($process->{pid}, 0) ;

return undef ;
}

# -----------------------------------------------------------------------------

my ($slow_input, $slow_writer) = pipe_pair() ;
my $slow = piped_discovery(input => $slow_input, timeout => 0.05, close => [$slow_writer]) ;

close $slow_input ;

syswrite($slow_writer, "\e") ;

Time::HiRes::sleep(0.4) ;

syswrite($slow_writer, '[A') ;

close $slow_writer ;

my $slow_output = read_all($slow->{output}) ;

is($slow_output, record('Esc', '1b') . record('[', '5b') . record('A', '41'), 'an escape that is followed by more bytes only after a pause is a key on its own') ;
is(finish_discovery($slow), 0, 'and discovery ends') ;

my ($patient_input, $patient_writer) = pipe_pair() ;
my $patient = piped_discovery(input => $patient_input, timeout => 2, close => [$patient_writer]) ;

close $patient_input ;

syswrite($patient_writer, "\e") ;

Time::HiRes::sleep(0.3) ;

syswrite($patient_writer, '[A') ;

close $patient_writer ;

is(read_all($patient->{output}), record('Up', '1b 5b 41'), 'with a longer wait the pieces are one key') ;
is(finish_discovery($patient), 0, 'and ends') ;

my ($live_input, $live_writer) = pipe_pair() ;
my $live = piped_discovery(input => $live_input, timeout => 0.05, close => [$live_writer]) ;

close $live_input ;

syswrite($live_writer, 'a') ;

like(read_until($live->{output}, qr/Sequence : 61\n\n/, 5), qr/Key      : a\n/, 'a key is reported as soon as it is typed, before the input ends') ;

syswrite($live_writer, "\e[B") ;

like(read_until($live->{output}, qr/Down/, 5), qr/Key      : Down/, 'and so is the next one') ;

syswrite($live_writer, "\e") ;

like(read_until($live->{output}, qr/Esc/, 5), qr/Key      : Esc\nSequence : 1b\n/, 'a lone escape is reported after the wait') ;

close $live_writer ;

is(finish_discovery($live), 0, 'discovery ends when the input ends') ;

# on the terminal of the user

my ($terminal, $slave) = new_terminal() ;

my $before  = termios_of($slave) ;
my $tty     = piped_discovery(input => $slave, timeout => 0.05) ;
my $started = read_until($tty->{error}, qr/\n/, 5) ;

like($started, qr/\APress keys to see what they send, Ctrl-C twice to stop\.\r\n\z/, 'on a terminal discovery says what to do, on the error output') ;
ok(!(termios_of($slave)->{lflag} & POSIX::ICANON()), 'the terminal is in raw mode') ;

syswrite($terminal, "\e[A") ;

is(read_until($tty->{output}, qr/Sequence : 1b 5b 41\r\n\r\n/, 5), "Key      : Up\r\nSequence : 1b 5b 41\r\n\r\n", 'a key typed on the terminal is reported at once, with lines that end in carriage return and newline') ;

is(read_until($terminal, qr/./, 0.4), '', 'and is not echoed by the terminal') ;

syswrite($terminal, "\x03") ;

like(read_until($tty->{output}, qr/C-c/, 5), qr/Key      : C-c\r\n/, 'Ctrl-C is a key') ;

syswrite($terminal, "\x03") ;

is(finish_discovery($tty), 0, 'a second Ctrl-C ends discovery') ;
is_deeply(termios_of($slave), $before, 'and the terminal is restored') ;

# the command line

my $script = "$FindBin::Bin/../keyfilter" ;

is(qx{printf 'a\\033[A\\177' | $^X $script --discover}, record('a', '61') . record('Up', '1b 5b 41') . record('Backspace', '7f'), 'keyfilter --discover reports the keys it reads') ;
is($? >> 8, 0, 'and ends with 0') ;
is(qx{printf '' | $^X $script --discover}, '', 'nothing to read, nothing to report') ;
is(qx{printf '\\003\\003a' | $^X $script --discover 2>&1}, record('C-c', '03') . record('C-c', '03'), 'Ctrl-C twice ends it') ;

my $script_output = qx{printf '\\033[1;5A' | $^X $script --discover} ;
my @fields        = split /\n/, $script_output ;

is_deeply(\@fields, ['Key      : C-Up', 'Sequence : 1b 5b 31 3b 35 41'], 'the output can be read by a script, line by line') ;
like($script_output, qr/\n\n\z/, 'and ends each key with a blank line') ;

done_testing ;
