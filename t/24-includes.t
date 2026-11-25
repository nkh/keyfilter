#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

write_file("$dir/common.profile", "map a=b\n", "block z\n") ;
write_file("$dir/main.profile", "block q\n", "include common.profile\n", "map c=d\n") ;

my $profile = KeyFilter::Profile::load("$dir/main.profile") ;

is_deeply([ map { $_->{cmd} } $profile->commands ], ['block', 'map', 'block', 'map'], 'included commands are inserted where the include is') ;
is_deeply([ map { $_->{key} // join('', @{$_->{keys}}) } $profile->commands ], ['q', 'a', 'z', 'c'], 'in the order of the files') ;
ok(!(grep { $_->{cmd} eq 'include' } $profile->commands), 'the include command itself is not kept') ;
is($profile->rules->process('a'), 'b', 'rules of the included file apply') ;
is($profile->rules->process('z'), '', 'blocks of the included file apply') ;
is($profile->rules->process('c'), 'd', 'rules after the include apply') ;

is_deeply([ map { $_->{source} } $profile->commands ], ["$dir/main.profile:1", "$dir/common.profile:1", "$dir/common.profile:2", "$dir/main.profile:3"], 'included commands keep their own file and line') ;

write_file("$dir/level2.profile", "map b=2\n") ;
write_file("$dir/level1.profile", "map a=1\n", "include level2.profile\n", "map c=3\n") ;
write_file("$dir/top.profile", "include level1.profile\n", "map d=4\n") ;

is_deeply([ map { $_->{key} } KeyFilter::Profile::load("$dir/top.profile")->commands ], ['a', 'b', 'c', 'd'], 'included files may include other files') ;

write_file("$dir/sub/inner.profile", "map i=1\n", "include ../common.profile\n", "include sibling.profile\n") ;
write_file("$dir/sub/sibling.profile", "map s=2\n") ;
write_file("$dir/outer.profile", "include sub/inner.profile\n") ;

is_deeply([ map { $_->{key} // 'block' } KeyFilter::Profile::load("$dir/outer.profile")->commands ], ['i', 'a', 'block', 's'], 'a relative path is relative to the including file') ;

write_file("$dir/absolute.profile", "include $dir/common.profile\n") ;

is(KeyFilter::Profile::load("$dir/absolute.profile")->rules->count, 2, 'an absolute path is used as it is') ;

write_file("$dir/twice.profile", "include common.profile\n", "include level2.profile\n") ;

is(scalar(() = KeyFilter::Profile::load("$dir/twice.profile")->commands), 3, 'several includes are all expanded') ;

write_file("$dir/startup.profile", "startup-delay 200\n") ;
write_file("$dir/withstartup.profile", "include startup.profile\n", "send-startup make\\n\n") ;

is_deeply([ map { $_->{cmd} } KeyFilter::Profile::load("$dir/withstartup.profile")->startup ], ['startup-delay', 'send-startup'], 'startup commands of an included file are kept') ;

write_file("$dir/missing.profile", "block a\n", "include nope.profile\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/missing.profile") ; }), qr/\A\Q$dir\E\/missing\.profile:2: missing include 'nope\.profile'/, 'a missing include is fatal and names the file and the line') ;

write_file("$dir/badinclude.profile", "include broken.profile\n") ;
write_file("$dir/broken.profile", "block a\n", "bogus\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/badinclude.profile") ; }), qr/\A\Q$dir\E\/broken\.profile:2: unknown command 'bogus'/, 'an error in an included file names that file') ;

write_file("$dir/noargument.profile", "include\n") ;

like(failure_of(sub { KeyFilter::Profile::load("$dir/noargument.profile") ; }), qr/noargument\.profile:1: include requires an argument/, 'an include without a file is fatal') ;

my @profiles = KeyFilter::Profile::load_profiles("$dir/main.profile", "$dir/level1.profile") ;

is(KeyFilter::Profile::build_rules(@profiles)->count, 7, 'includes work with several profiles') ;

done_testing ;
