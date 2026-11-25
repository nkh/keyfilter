#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use Cwd () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $home = temp_dir() ;

local $ENV{HOME} = "$home" ;

is(KeyFilter::Profile::config_dir(), "$home/.config/keyfilter", 'the user directory is under the home directory') ;

write_file("$home/.config/keyfilter/vim.profile", "map a=v\n") ;
write_file("$home/.config/keyfilter/gaming.profile", "map a=g\n", "block q\n") ;

is(KeyFilter::Profile::find_profile('vim'), "$home/.config/keyfilter/vim.profile", 'a name is looked for in the user directory') ;

my @profiles = KeyFilter::Profile::load_profiles('vim') ;

is($profiles[0]->name, 'vim', 'a profile is loaded by name') ;
is($profiles[0]->rules->process('a'), 'v', 'with its rules') ;

my @two = KeyFilter::Profile::load_profiles('vim', 'gaming') ;

is_deeply([ map { $_->name } @two ], ['vim', 'gaming'], 'several names keep their order') ;
is(KeyFilter::Profile::build_rules(@two)->process('a'), 'g', 'and combine into rules') ;

my $work = temp_dir() ;

write_file("$work/local.profile", "map a=l\n") ;
write_file("$work/up/test.profile", "map a=t\n") ;
write_file("$work/vim.profile", "map a=w\n") ;
write_file("$work/other.profile", "map a=o\n") ;

my $original = Cwd::getcwd() ;

chdir "$work/up" or die "chdir: $!" ;

is(KeyFilter::Profile::find_profile('../local.profile'), '../local.profile', 'a name with a path separator is used as it is') ;
is(KeyFilter::Profile::find_profile('./test.profile'), './test.profile', 'also when it starts with a dot') ;
is(KeyFilter::Profile::find_profile("$work/local.profile"), "$work/local.profile", 'and when it is absolute') ;

is((KeyFilter::Profile::load_profiles('../local.profile'))[0]->rules->process('a'), 'l', 'a profile is loaded directly from a relative path') ;
is((KeyFilter::Profile::load_profiles('./test.profile'))[0]->rules->process('a'), 't', 'from the current directory') ;
is((KeyFilter::Profile::load_profiles('vim'))[0]->rules->process('a'), 'v', 'a name is not looked for in the current directory') ;

chdir $original or die "chdir: $!" ;

my @mixed = KeyFilter::Profile::load_profiles('vim', "$work/local.profile", 'gaming') ;

is_deeply([ map { $_->name } @mixed ], ['vim', 'local', 'gaming'], 'names and paths can be mixed') ;
is(KeyFilter::Profile::build_rules(@mixed)->process('a'), 'g', 'in the given order') ;

chdir $work or die "chdir: $!" ;

like(failure_of(sub { KeyFilter::Profile::find_profile('other') ; }), qr/missing profile 'other', looked for '\Q$home\E\/\.config\/keyfilter\/other\.profile'/, 'a name that is only in the current directory is missing') ;

chdir $original or die "chdir: $!" ;

like(failure_of(sub { KeyFilter::Profile::load_profiles('nope') ; }), qr/missing profile 'nope', looked for '\Q$home\E\/\.config\/keyfilter\/nope\.profile'/, 'a missing profile is fatal and the message says where it was looked for') ;
like(failure_of(sub { KeyFilter::Profile::load_profiles('./nope.profile') ; }), qr/missing profile '\.\/nope\.profile', looked for '\.\/nope\.profile'/, 'a missing profile with a path is fatal') ;
like(failure_of(sub { KeyFilter::Profile::load_profiles('vim.profile') ; }), qr/missing profile 'vim\.profile'/, 'the .profile suffix is added to the name, not expected in it') ;

{
local $ENV{HOME} ;

delete $ENV{HOME} ;

like(failure_of(sub { KeyFilter::Profile::find_profile('vim') ; }), qr/HOME is not set/, 'without a home directory a name cannot be looked up') ;
is(KeyFilter::Profile::find_profile("$work/local.profile"), "$work/local.profile", 'but a path still works') ;
}

done_testing ;
