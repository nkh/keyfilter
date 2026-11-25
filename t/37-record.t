#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

sub fd_count { opendir(my $d, '/proc/self/fd') or die ; return scalar(() = readdir $d) ; }

# -----------------------------------------------------------------------------

sub startup_from { return KeyFilter::Startup->new(map { scalar KeyFilter::Command::parse_command($_) } @_) ; }

# -----------------------------------------------------------------------------

sub events_of { my ($path) = @_ ; return KeyFilter::Recorder::parse_recording(read_file($path)) ; }

# -----------------------------------------------------------------------------

sub joined { my ($type, @events) = @_ ; return join('', map { $_->{data} } grep { $_->{type} eq $type } @events) ; }

# -----------------------------------------------------------------------------

# encoding

my @encodings =
	(
	['', ''],
	['abc', 'abc'],
	['a b', 'a b'],
	[' leading', ' leading'],
	['trailing ', 'trailing '],
	["\n", '\n'],
	["\r", '\r'],
	["\t", '\t'],
	["\e", '\e'],
	["\\", '\\\\'],
	["\\n", '\\\\n'],
	['\x41', '\\\\x41'],
	["\x00", '\x00'],
	["\x1f", '\x1f'],
	["\x7f", '\x7f'],
	["\x80", '\x80'],
	["\xff", '\xff'],
	["\xc3\xa9", '\xc3\xa9'],
	['~', '~'],
	['!', '!'],
	["\e[A", '\e[A'],
	["line1\r\nline2", 'line1\r\nline2'],
	['# not a comment', '# not a comment'],
	) ;

for my $case (@encodings)
	{
	my ($bytes, $text) = @$case ;
	
	is(KeyFilter::Recorder::encode($bytes), $text, 'encode ' . unpack('H*', $bytes)) ;
	is(KeyFilter::Recorder::decode($text), $bytes, 'decode ' . $text) ;
	}

my $roundtrip = 0 ;

for my $value (0 .. 255)
	{
	$roundtrip++ unless KeyFilter::Recorder::decode(KeyFilter::Recorder::encode(chr $value)) eq chr $value ;
	}

is($roundtrip, 0, 'every byte value survives a round trip') ;

my $everything = join('', map { chr } 0 .. 255) ;
my $encoded    = KeyFilter::Recorder::encode($everything) ;

like($encoded, qr/\A[\x20-\x7e]*\z/, 'an encoded text is printable ascii and has no line end') ;
is(KeyFilter::Recorder::decode($encoded), $everything, 'all the bytes together survive a round trip') ;

srand(5) ;

my $bad = 0 ;

for (1 .. 300)
	{
	my $bytes = join('', map { chr int rand 256 } 1 .. int rand 60) ;
	my $text  = KeyFilter::Recorder::encode($bytes) ;
	
	$bad++ unless KeyFilter::Recorder::decode($text) eq $bytes && $text !~ /[^\x20-\x7e]/ ;
	}

is($bad, 0, 'random binary data survives a round trip') ;

is(KeyFilter::Recorder::decode('\xFF'), "\xff", 'hexadecimal digits can be in upper case') ;
is(KeyFilter::Recorder::decode('a\nb\\\\c'), "a\nb\\c", 'escapes are resolved inside text') ;

for my $case (['\q', qr/unknown escape '\\q'/], ['\X41', qr/unknown escape '\\X'/], ['ab\\', qr/trailing backslash/], ['\x4', qr/unknown escape '\\x'/], ['\xzz', qr/unknown escape '\\x'/])
	{
	my ($text, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Recorder::decode($text) ; }), $pattern, "decode refuses $text") ;
	}

# the file

my $path = "$dir/first.rec" ;
my $rec  = KeyFilter::Recorder->new(file => $path, clock => sub { 0 }) ;

isa_ok($rec, 'KeyFilter::Recorder') ;
is(read_file($path), "# keyfilter-recording 1\n", 'a recording starts with a header') ;

$rec->record_input('hello') ;

is(read_file($path), "# keyfilter-recording 1\n0.000000 I hello\n", 'input is written as soon as it is recorded') ;

$rec->record_output("hi\r\n") ;

is(read_file($path), "# keyfilter-recording 1\n0.000000 I hello\n0.000000 O hi\\r\\n\n", 'so is output') ;

$rec->record_input('') ;
$rec->record_output('') ;
$rec->record_input(undef) ;

is(read_file($path), "# keyfilter-recording 1\n0.000000 I hello\n0.000000 O hi\\r\\n\n", 'nothing is recorded for nothing') ;

$rec->record_output("\x00\xff") ;
$rec->record_input('  spaces  ') ;

is(read_file($path), "# keyfilter-recording 1\n0.000000 I hello\n0.000000 O hi\\r\\n\n0.000000 O \\x00\\xff\n0.000000 I   spaces  \n", 'binary data and spaces are kept') ;

is($rec->close, $rec, 'close returns the recorder') ;

$rec->record_input('late') ;

is(read_file($path), "# keyfilter-recording 1\n0.000000 I hello\n0.000000 O hi\\r\\n\n0.000000 O \\x00\\xff\n0.000000 I   spaces  \n", 'nothing is written after close') ;
is($rec->close, $rec, 'closing twice is fine') ;

write_file("$dir/old.rec", "old content that is longer than a header\n" x 10) ;

KeyFilter::Recorder->new(file => "$dir/old.rec")->close ;

is(read_file("$dir/old.rec"), "# keyfilter-recording 1\n", 'an existing file is replaced') ;

like(failure_of(sub { KeyFilter::Recorder->new(file => "$dir/missing/dir/x.rec") ; }), qr/\Acannot write the recording '\Q$dir\E\/missing\/dir\/x\.rec': No such file or directory/, 'a file that cannot be written is fatal') ;
like(failure_of(sub { KeyFilter::Recorder->new() ; }), qr/needs a file or a handle/, 'a recording needs somewhere to go') ;

open(my $handle, '>', "$dir/handle.rec") or die ;

my $to_handle = KeyFilter::Recorder->new(handle => $handle, clock => sub { 0 }) ;

$to_handle->record_input('abc') ;
$to_handle->close ;

print $handle "after\n" ;

close $handle ;

is(read_file("$dir/handle.rec"), "# keyfilter-recording 1\n0.000000 I abc\nafter\n", 'a recording on a handle does not close it') ;

SKIP:
	{
	skip 'no /proc', 1 unless -d '/proc/self/fd' ;
	
	my $before = fd_count() ;
	my $opened = KeyFilter::Recorder->new(file => "$dir/fd.rec") ;
	
	is(fd_count(), $before + 1, 'a recording on a file holds one descriptor') ;
	
	$opened->close ;
	
	is(fd_count(), $before, 'which close releases') ;
	}

# each event is one line, whatever the data

my $lines = KeyFilter::Recorder->new(file => "$dir/lines.rec") ;

$lines->record_output(join('', map { chr } 0 .. 255)) ;
$lines->record_input("a\nb\rc\n\n") ;
$lines->record_output('x' x 100000) ;
$lines->close ;

my @file_lines = split /\n/, read_file("$dir/lines.rec"), -1 ;

is(scalar @file_lines, 5, 'three events are three lines, plus the header and the end of the last line') ;
is($file_lines[4], '', 'ending with a line end') ;
cmp_ok(length $file_lines[3], '>', 100000, 'a long event is a long line') ;

# reading a recording

my @events = KeyFilter::Recorder::parse_recording(read_file("$dir/lines.rec")) ;

is_deeply([ map { $_->{type} } @events ], ['O', 'I', 'O'], 'events come back in order') ;
is($events[0]{data}, join('', map { chr } 0 .. 255), 'with their data') ;
is($events[1]{data}, "a\nb\rc\n\n", 'whatever it was') ;
is(length $events[2]{data}, 100000, 'and their size') ;

my @read = KeyFilter::Recorder::parse_recording("# header\n\n0.000000 I a\n   \n# comment\n0.000001 O b\n") ;

is_deeply([ map { "$_->{type}$_->{data}" } @read ], ['Ia', 'Ob'], 'comments and blank lines are ignored') ;

@read = KeyFilter::Recorder::parse_recording("0.000000 I  two spaces\n0.000000 I\n0.000000 O \n") ;

is_deeply([ map { $_->{data} } @read ], [' two spaces', '', ''], 'only the space after the type is not part of the data') ;

is_deeply([ KeyFilter::Recorder::parse_recording('') ], [], 'an empty recording has no event') ;

like(failure_of(sub { KeyFilter::Recorder::parse_recording("0.000000 I a\n0.000000 Z b\n") ; }), qr/\Arecording line 2: invalid event/, 'an unknown event is fatal and names its line') ;
like(failure_of(sub { KeyFilter::Recorder::parse_recording("0.000000 I a\n\n0.000000 O \\q\n") ; }), qr/\Arecording line 3: unknown escape '\\q'/, 'a bad escape is fatal and names its line') ;
like(failure_of(sub { KeyFilter::Recorder::parse_recording("0.000000 i a\n") ; }), qr/recording line 1: invalid event/, 'the type is in upper case') ;

# recording a run

my $in = KeyFilter::Recorder->new(file => "$dir/cat.rec") ;
my $cat = run_engine({ recorder => $in, input_data => "hello\n" }, 'cat') ;

my @cat_events = events_of("$dir/cat.rec") ;

is(joined('I', @cat_events), "hello\n\x04", 'what the child received is recorded, the end of the input too') ;
is(joined('O', @cat_events), $cat->{output}, 'what it wrote is recorded exactly as it was forwarded') ;
is($cat_events[0]{type}, 'I', 'the input comes first') ;

my $shell = KeyFilter::Recorder->new(file => "$dir/shell.rec") ;

run_engine({ recorder => $shell, input_data => "abc\n" }, 'sh', '-c', 'read x ; echo got:$x') ;

my @shell_events = events_of("$dir/shell.rec") ;
my ($first_output) = grep { $shell_events[$_]{type} eq 'O' && $shell_events[$_]{data} =~ /got:abc/ } 0 .. $#shell_events ;

ok(defined $first_output, 'the answer of the child is recorded') ;

my ($first_input) = grep { $shell_events[$_]{type} eq 'I' } 0 .. $#shell_events ;

cmp_ok($first_input, '<', $first_output, 'after the input that caused it') ;

my $upper = KeyFilter::Recorder->new(file => "$dir/upper.rec") ;

run_engine({ recorder => $upper, input_data => "abc\n", filter => sub { return uc $_[0] ; } }, 'cat') ;

like(joined('I', events_of("$dir/upper.rec")), qr/\AABC\n/, 'input is recorded after the filter, as the child received it') ;

my $blocked = KeyFilter::Recorder->new(file => "$dir/blocked.rec") ;

run_engine({ recorder => $blocked, input_data => "secret\n", filter => sub { return '' ; } }, 'sh', '-c', 'sleep 0.3') ;

unlike(joined('I', events_of("$dir/blocked.rec")), qr/secret/, 'input that a filter blocks is not recorded') ;

my $started = KeyFilter::Recorder->new(file => "$dir/startup.rec") ;
my ($startup_input, $startup_writer) = pipe_pair() ;

my $with_startup = KeyFilter::PTY->new(command => ['sh', '-c', 'read x ; echo got:$x'], input => $startup_input, output => do { open(my $null, '>', '/dev/null') ; $null }, recorder => $started, startup => startup_from('send-startup typed\n')) ;

$with_startup->run ;

is(joined('I', events_of("$dir/startup.rec")), "typed\n", 'the text of a startup is recorded as input') ;

my $binary = KeyFilter::Recorder->new(file => "$dir/binary.rec") ;
my $raw    = run_engine({ recorder => $binary }, 'sh', '-c', 'stty raw -echo ; "$0" -e "print map { chr } 0 .. 255"', $^X) ;

is(joined('O', events_of("$dir/binary.rec")), join('', map { chr } 0 .. 255), 'binary output is recorded exactly') ;

my $large = KeyFilter::Recorder->new(file => "$dir/large.rec") ;

run_engine({ recorder => $large }, 'sh', '-c', 'stty raw -echo ; "$0" -e "print q(0123456789) x 100000"', $^X) ;

is(joined('O', events_of("$dir/large.rec")), '0123456789' x 100000, 'a large output is recorded completely') ;

my @seen ;
my $both = KeyFilter::Recorder->new(file => "$dir/both.rec") ;
my $together = run_engine({ recorder => $both, on_output => sub { push @seen, $_[0] ; } }, 'echo', 'both') ;

is(join('', @seen), "both\r\n", 'the output callback still works with a recorder') ;
is(joined('O', events_of("$dir/both.rec")), "both\r\n", 'and the recorder gets the output too') ;

my $plain = run_engine({}, 'echo', 'plain') ;

is($plain->{output}, "plain\r\n", 'a run without a recorder is as before') ;

SKIP:
	{
	skip 'no /proc', 2 unless -d '/proc/self/fd' ;
	
	my $closing = KeyFilter::Recorder->new(file => "$dir/closing.rec") ;
	my $before  = fd_count() ;
	
	run_engine({ recorder => $closing }, 'echo', 'x') ;
	
	is(fd_count(), $before - 1, 'the recorder is closed when the run ends') ;
	
	my $failing = KeyFilter::Recorder->new(file => "$dir/failing.rec") ;
	
	$before = fd_count() ;
	
	my $failed = run_engine({ recorder => $failing, input_data => "abc\n", filter => sub { die "boom\n" ; } }, 'sleep', '5') ;
	
	my $failed_pid = $failed->{pty}->pid ;
	
	like($failed->{error}, qr/\Aboom/, 'a run that fails reports it') ;
	
	undef $failed ;
	
	is(fd_count(), $before - 1, 'and still closes the recorder') ;
	
	kill 'KILL', -$failed_pid if defined $failed_pid ;
	}

is(read_file("$dir/failing.rec"), "# keyfilter-recording 1\n", 'a failed run leaves a complete recording, here only the header') ;

done_testing ;
