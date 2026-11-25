#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

sub keys_of { return map { $_->{key} // join('', @{$_->{keys}}) } $_[0]->commands ; }

my $dir = temp_dir() ;

write_file("$dir/common.profile", "map c=1\n", "map d=2\n") ;

write_file("$dir/loop-a.profile", "map a=1\n", "include loop-b.profile\n") ;
write_file("$dir/loop-b.profile", "map b=2\n", "include loop-a.profile\n") ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/loop-a.profile")) ], ['a', 'b'], 'an include loop ends, each file is loaded once') ;

write_file("$dir/self.profile", "map a=1\n", "include self.profile\n", "map b=2\n") ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/self.profile")) ], ['a', 'b'], 'a file that includes itself is ignored the second time') ;

write_file("$dir/twice.profile", "include common.profile\n", "map x=3\n", "include common.profile\n") ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/twice.profile")) ], ['c', 'd', 'x'], 'a file included twice is loaded once, at the first include') ;

write_file("$dir/base.profile", "map e=1\n") ;
write_file("$dir/left.profile", "map l=1\n", "include base.profile\n") ;
write_file("$dir/right.profile", "map r=1\n", "include base.profile\n") ;
write_file("$dir/diamond.profile", "include left.profile\n", "include right.profile\n") ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/diamond.profile")) ], ['l', 'e', 'r'], 'a shared include of two files is loaded once') ;

write_file("$dir/spellings.profile", "include common.profile\n", "include ./common.profile\n", "include sub/../common.profile\n", "include $dir/common.profile\n") ;
mkdir "$dir/sub" ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/spellings.profile")) ], ['c', 'd'], 'different spellings of a path are the same file') ;

symlink("$dir/common.profile", "$dir/link.profile") or die "symlink: $!" ;

write_file("$dir/symlinks.profile", "include common.profile\n", "include link.profile\n") ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/symlinks.profile")) ], ['c', 'd'], 'a symbolic link to a loaded file is the same file') ;

write_file("$dir/one.profile", "map o=1\n", "include common.profile\n") ;
write_file("$dir/two.profile", "map t=2\n", "include common.profile\n") ;

my @profiles = KeyFilter::Profile::load_profiles("$dir/one.profile", "$dir/two.profile") ;

is_deeply([ keys_of($profiles[0]) ], ['o', 'c', 'd'], 'the first profile loads the shared include') ;
is_deeply([ keys_of($profiles[1]) ], ['t'], 'the second profile does not load it again') ;
is(KeyFilter::Profile::build_rules(@profiles)->count, 4, 'the combined rules have it once') ;

is_deeply([ keys_of(KeyFilter::Profile::load("$dir/one.profile")) ], ['o', 'c', 'd'], 'a profile loaded alone loads its includes') ;
is_deeply([ keys_of(KeyFilter::Profile::load("$dir/two.profile")) ], ['t', 'c', 'd'], 'and so does another profile loaded alone') ;

write_file("$dir/profile-a.profile", "map a=1\n") ;
write_file("$dir/profile-b.profile", "map b=2\n", "include profile-a.profile\n") ;

my @ab = KeyFilter::Profile::load_profiles("$dir/profile-a.profile", "$dir/profile-b.profile") ;

is_deeply([ keys_of($ab[1]) ], ['b'], 'including a file that is already loaded as a profile is ignored') ;

my @again = KeyFilter::Profile::load_profiles("$dir/one.profile", "$dir/one.profile") ;

is_deeply([ keys_of($again[0]) ], ['o', 'c', 'd'], 'a profile listed twice loads the first time') ;
is_deeply([ keys_of($again[1]) ], ['o'], 'and loads its own commands the second time, without the includes') ;

write_file("$dir/ignored.profile", "include common.profile\n", "include nope.profile\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/ignored.profile") ; }), qr/ignored\.profile:2: missing include 'nope\.profile'/, 'a missing include is still fatal') ;

done_testing ;
