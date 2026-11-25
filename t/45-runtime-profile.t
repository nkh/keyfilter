#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

sub parsed { return map { scalar KeyFilter::Command::parse_command($_) } @_ ; }

# -----------------------------------------------------------------------------

sub profile_with
{
my ($name, @lines) = @_ ;

write_file("$dir/$name.profile", map { "$_\n" } @lines) ;

return KeyFilter::Profile::load("$dir/$name.profile") ;
}

# -----------------------------------------------------------------------------

# the layers

my $empty = KeyFilter::Chain->new() ;

isa_ok($empty, 'KeyFilter::Chain') ;
is_deeply([ $empty->order ], ['keyfilter_command_line', 'keyfilter_runtime'], 'an empty chain has the command line and the runtime') ;
is($empty->rules->count, 0, 'and no rule') ;
is_deeply([ $empty->runtime_commands ], [], 'no runtime command') ;
is_deeply([ $empty->command_line_commands ], [], 'and no command line command') ;
is(KeyFilter::Chain::command_line_name(), 'keyfilter_command_line', 'the command line profile has a name') ;
is(KeyFilter::Chain::runtime_name(), 'keyfilter_runtime', 'and so has the runtime profile') ;

my $vim    = profile_with('vim', 'block C-z', 'map F1=vim') ;
my $gaming = profile_with('gaming', 'map F1=game', 'block q') ;

my $chain = KeyFilter::Chain->new(profiles => [$vim, $gaming], command_line => [ parsed('block x', 'map y=z') ]) ;

is_deeply([ $chain->order ], ['vim', 'gaming', 'keyfilter_command_line', 'keyfilter_runtime'], 'the active order is the profiles, the command line and the runtime') ;
is_deeply([ map { $_->name } $chain->profiles ], ['vim', 'gaming'], 'the profiles keep the order they were given in') ;
is(scalar(() = $chain->command_line_commands), 2, 'the command line commands are kept') ;

is_deeply([ map { $_->{cmd} } $chain->commands ], ['block', 'map', 'map', 'block', 'block', 'map'], 'the commands are those of the profiles, then the command line') ;

# runtime commands

is($chain->add_runtime(scalar KeyFilter::Command::parse_command('block w')), $chain, 'adding a runtime command returns the chain') ;
is(scalar(() = $chain->runtime_commands), 1, 'the command is kept') ;

$chain->add_runtime($_) for parsed('unblock x', 'map F1=runtime') ;

is_deeply([ map { $_->{cmd} } $chain->runtime_commands ], ['block', 'unblock', 'map'], 'runtime commands keep the order they came in') ;
is_deeply([ map { $_->{cmd} } $chain->commands ], ['block', 'map', 'map', 'block', 'block', 'map', 'block', 'unblock', 'map'], 'and come last') ;
is($chain->rules->count, 9, 'all of them are rules') ;

my $rules = $chain->rules ;

is($rules->process("\x1a"), '', 'a block of the first profile applies') ;
is($rules->process('q'), '', 'and one of the second') ;
is($rules->process('x'), 'x', 'a runtime unblock overrides a command line block') ;
is($rules->process('w'), '', 'a runtime block applies') ;
is($rules->process("\eOP"), 'runtime', 'a runtime map overrides the maps of the profiles') ;
is($rules->process('y'), 'z', 'a command line map applies') ;
is($rules->process('a'), 'a', 'other keys pass') ;

$chain->add_runtime($_) for parsed('map y=again') ;

is($chain->rules->process('y'), 'again', 'a runtime map overrides the command line') ;
is($rules->process('y'), 'z', 'rules that were given out are not changed') ;

my $against = KeyFilter::Chain->new(profiles => [ profile_with('base', 'block a') ]) ;

$against->add_runtime($_) for parsed('unblock a') ;

is($against->rules->process('a'), 'a', 'a runtime unblock overrides a profile block') ;

my $layers = KeyFilter::Chain->new(profiles => [ profile_with('layer', 'unblock b') ], command_line => [ parsed('block b') ]) ;

is($layers->rules->process('b'), '', 'the command line comes after the profiles') ;

$layers->add_runtime($_) for parsed('unblock b') ;

is($layers->rules->process('b'), 'b', 'and the runtime after the command line') ;

# what is accepted

for my $line ('send abc', 'toggle gaming', 'startup-delay 5', 'send-startup x', 'include f', 'profile vim')
	{
	my ($name) = $line =~ /\A(\S+)/ ;
	
	like(failure_of(sub { $chain->add_runtime(scalar KeyFilter::Command::parse_command($line)) ; }), qr/\Anot a rule command '$name'/, "$name is not a runtime rule") ;
	}

like(failure_of(sub { $chain->add_runtime('block a') ; }), qr/\Anot a rule command ''/, 'text is not a command') ;
like(failure_of(sub { $chain->add_runtime(undef) ; }), qr/\Anot a rule command ''/, 'undef is not a command') ;

is(scalar(() = $chain->runtime_commands), 4, 'refused commands are not kept') ;

for my $line ('send abc', 'toggle gaming', 'include f', 'profile vim')
	{
	my ($name) = $line =~ /\A(\S+)/ ;
	
	like(failure_of(sub { KeyFilter::Chain->new(command_line => [ scalar KeyFilter::Command::parse_command($line) ]) ; }), qr/\Anot a command line command '$name'/, "$name is not a command line command") ;
	}

like(failure_of(sub { KeyFilter::Chain->new(profiles => ['vim']) ; }), qr/\Anot a profile/, 'a profile must be a profile') ;
like(failure_of(sub { KeyFilter::Chain->new(profiles => [undef]) ; }), qr/\Anot a profile/, 'not undef') ;
like(failure_of(sub { KeyFilter::Chain->new(command_line => ['block a']) ; }), qr/\Anot a command line command ''/, 'and a command line command must be a command') ;

write_file("$dir/keyfilter_runtime.profile", "block a\n") ;
write_file("$dir/keyfilter_command_line.profile", "block a\n") ;

like(failure_of(sub { KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$dir/keyfilter_runtime.profile") ]) ; }), qr/\Areserved profile name 'keyfilter_runtime'/, 'a profile cannot take the name of the runtime profile') ;
like(failure_of(sub { KeyFilter::Chain->new(profiles => [ KeyFilter::Profile::load("$dir/keyfilter_command_line.profile") ]) ; }), qr/\Areserved profile name 'keyfilter_command_line'/, 'or of the command line profile') ;

# runtime commands are for one instance

my $other = KeyFilter::Chain->new(profiles => [$vim, $gaming]) ;

is_deeply([ $other->runtime_commands ], [], 'another chain on the same profiles has no runtime command') ;
is($other->rules->process('w'), 'w', 'and its rules are not changed') ;

my $fresh = KeyFilter::Chain->new(profiles => [$vim, $gaming], command_line => [ parsed('block x', 'map y=z') ]) ;

is_deeply([ $fresh->runtime_commands ], [], 'a new chain starts without runtime commands, they are gone with the old one') ;

# profile files are never changed

my $file = "$dir/vim.profile" ;
my $text = read_file($file) ;
my $time = (stat $file)[9] ;

$chain->add_runtime($_) for parsed('block m', 'map n=o') ;
$chain->rules ;

is(read_file($file), $text, 'runtime commands do not change a profile file') ;
is((stat $file)[9], $time, 'not even its time') ;

opendir(my $handle, $dir) or die ;

my @files = sort grep { /\.profile\z/ } readdir $handle ;

closedir $handle ;

is_deeply(\@files, ['base.profile', 'gaming.profile', 'keyfilter_command_line.profile', 'keyfilter_runtime.profile', 'layer.profile', 'vim.profile'], 'and no file is created for them') ;

is_deeply([ map { $_->{cmd} } $vim->commands ], ['block', 'map'], 'the commands of a profile are not changed either') ;

# startup commands

my $starting = KeyFilter::Chain->new(
	profiles     => [ profile_with('s1', 'send-startup one', 'startup-delay 100', 'block a'), profile_with('s2', 'send-startup two') ],
	command_line => [ parsed('send-startup three', 'startup-delay 300') ],
	) ;

$starting->add_runtime($_) for parsed('block b') ;

my $startup = $starting->startup ;

isa_ok($startup, 'KeyFilter::Startup') ;
is_deeply([ $startup->actions ], ['one', 'two', 'three'], 'the startup actions are those of the profiles then of the command line') ;
is($startup->delay_ms, 300, 'and a delay on the command line wins over a profile') ;

my $profile_delay = KeyFilter::Chain->new(profiles => [ profile_with('s3', 'startup-delay 700') ]) ;

is($profile_delay->startup->delay_ms, 700, 'a delay of a profile is used') ;
is(KeyFilter::Chain->new()->startup->delay_ms, 0, 'no delay is no delay') ;
is($starting->rules->count, 2, 'startup commands are not rules') ;

# with real files, includes included

write_file("$dir/common.profile", "block c\n", "send-startup from-common\n") ;
write_file("$dir/main.profile", "block m\n", "include common.profile\n", "map d=e\n") ;

my @loaded = KeyFilter::Profile::load_profiles("$dir/main.profile", "$dir/vim.profile") ;
my $real   = KeyFilter::Chain->new(profiles => \@loaded) ;

is_deeply([ $real->order ], ['main', 'vim', 'keyfilter_command_line', 'keyfilter_runtime'], 'profiles loaded from files make a chain') ;
is_deeply([ map { $_->{cmd} } $real->commands ], ['block', 'block', 'send-startup', 'map', 'block', 'map'], 'with the included commands where the include is') ;
is($real->rules->process('c'), '', 'the included rules apply') ;
is_deeply([ $real->startup->actions ], ['from-common'], 'and the included startup commands') ;

done_testing ;
