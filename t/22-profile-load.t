#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

write_file
	(
	"$dir/vim.profile",
	"# vim profile\n",
	"\n",
	"block C-z # no suspend\n",
	"map F1=git status\\n\n",
	"startup-delay 500\n",
	"send-startup source env.sh\\n\n",
	"toggle gaming\n",
	"unblock C-z\n",
	) ;

my $profile = KeyFilter::Profile::load("$dir/vim.profile") ;

isa_ok($profile, 'KeyFilter::Profile') ;
is($profile->name, 'vim', 'the name is the file name without .profile') ;
is($profile->path, "$dir/vim.profile", 'the path is kept') ;
is_deeply([ map { $_->{cmd} } $profile->commands ], ['block', 'map', 'startup-delay', 'send-startup', 'toggle', 'unblock'], 'commands are in file order, comments and blank lines are ignored') ;
is_deeply([ map { $_->{source} } $profile->commands ], [map { "$dir/vim.profile:$_" } 3 .. 8], 'every command knows its file and line') ;

my $rules = $profile->rules ;

is($rules->count, 3, 'only block, unblock and map are rules') ;
is($rules->process("\eOP"), "git status\n", 'the rules of the profile are applied') ;
is($rules->process("\x1a"), "\x1a", 'block followed by unblock lets the key pass') ;
is($rules->process('a'), 'a', 'other keys pass') ;

my @startup = $profile->startup ;

is_deeply([ map { $_->{cmd} } @startup ], ['startup-delay', 'send-startup'], 'startup commands are kept apart from rules') ;
is($startup[0]{ms}, 500, 'the startup delay is kept') ;
is($startup[1]{text}, "source env.sh\n", 'the startup text is kept') ;

write_file("$dir/crlf.profile", "block a\r\n", "map b=c\r\n") ;

my $crlf = KeyFilter::Profile::load("$dir/crlf.profile") ;

is($crlf->rules->process('b'), 'c', 'CRLF line ends are accepted') ;
is($crlf->rules->process('a'), '', 'and do not end up in the commands') ;

write_file("$dir/no-newline.profile", "block a\n", "map b=c") ;

is(KeyFilter::Profile::load("$dir/no-newline.profile")->rules->count, 2, 'the last line needs no newline') ;

write_file("$dir/empty.profile", '') ;

is_deeply([ KeyFilter::Profile::load("$dir/empty.profile")->commands ], [], 'an empty profile has no commands') ;
is(KeyFilter::Profile::load("$dir/empty.profile")->rules->count, 0, 'and no rules') ;

write_file("$dir/my.local.profile", "block a\n") ;

is(KeyFilter::Profile::load("$dir/my.local.profile")->name, 'my.local', 'only the last suffix is removed from the name') ;

write_file("$dir/bad.profile", "block a\n", "bogus x\n", "map b=c\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/bad.profile") ; }), qr/\A\Q$dir\E\/bad\.profile:2: unknown command 'bogus'/, 'an error names the file and the line') ;

write_file("$dir/badkey.profile", "# comment\n", "block nokey\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/badkey.profile") ; }), qr/badkey\.profile:2: unknown key specification 'nokey'/, 'a key error names the file and the line') ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/nope.profile") ; }), qr/missing profile '\Q$dir\E\/nope\.profile'/, 'a missing profile is fatal') ;

my @parsed = KeyFilter::Command::parse_commands("block a\n\n# comment\nmap b=c", 'text') ;

is_deeply([ map { $_->{source} } @parsed ], ['text:1', 'text:4'], 'parse_commands numbers the lines of a text') ;
like(failure_of(sub { KeyFilter::Command::parse_commands("block a\nmap", 'text') ; }), qr/\Atext:2: invalid syntax/, 'parse_commands reports the failing line') ;

my @commands = map { scalar KeyFilter::Command::parse_command($_) } ('block a', 'send x', 'map b=c', 'toggle p') ;

is(KeyFilter::Rules->new()->add_commands(@commands)->count, 2, 'add_commands keeps the rule commands only') ;

done_testing ;
