#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir = temp_dir() ;

write_file("$dir/a.profile", "map a=b\n", "block x\n", "startup-delay 100\n") ;
write_file("$dir/b.profile", "map a=c\n", "unblock x\n", "send-startup make\\n\n") ;
write_file("$dir/c.profile", "map c=d\n") ;

my @profiles = KeyFilter::Profile::load_profiles("$dir/a.profile", "$dir/b.profile") ;

is(scalar @profiles, 2, 'two profiles are loaded') ;
is_deeply([ map { $_->name } @profiles ], ['a', 'b'], 'in the order they were given') ;

my $rules = KeyFilter::Profile::build_rules(@profiles) ;

is($rules->count, 4, 'the rules of both profiles are combined') ;
is_deeply([ map { $_->{cmd} } $rules->rules ], ['map', 'block', 'map', 'unblock'], 'profile order, then declaration order') ;
is($rules->process('a'), 'c', 'the map of the later profile wins') ;
is($rules->process('x'), 'x', 'the unblock of the later profile re-enables the key') ;
is($rules->process('z'), 'z', 'other keys pass') ;

my $reversed = KeyFilter::Profile::build_rules(reverse @profiles) ;

is($reversed->process('a'), 'b', 'with the order reversed the other map wins') ;
is($reversed->process('x'), '', 'and the key stays blocked') ;

my @startup = KeyFilter::Profile::build_startup(@profiles) ;

is_deeply([ map { $_->{cmd} } @startup ], ['startup-delay', 'send-startup'], 'startup commands are combined in profile order') ;

my @three = KeyFilter::Profile::load_profiles("$dir/a.profile", "$dir/b.profile", "$dir/c.profile") ;

is(KeyFilter::Profile::build_rules(@three)->process('c'), 'd', 'three profiles are combined') ;
is(KeyFilter::Profile::build_rules(@three)->count, 5, 'and give all their rules') ;

is(KeyFilter::Profile::build_rules()->count, 0, 'no profile gives no rules') ;
is_deeply([ KeyFilter::Profile::build_startup() ], [], 'and no startup commands') ;
is_deeply([ KeyFilter::Profile::load_profiles() ], [], 'loading no profile gives no profile') ;

my @same = KeyFilter::Profile::load_profiles("$dir/a.profile", "$dir/a.profile") ;

is(scalar @same, 2, 'the same profile can be loaded twice') ;

write_file("$dir/bad.profile", "block a\n", "bogus\n") ;

like(failure_of(sub { KeyFilter::Profile::load_profiles("$dir/a.profile", "$dir/bad.profile") ; }), qr/bad\.profile:2: unknown command 'bogus'/, 'an error names the profile that failed') ;
like(failure_of(sub { KeyFilter::Profile::load_profiles("$dir/a.profile", "$dir/nope.profile") ; }), qr/missing profile '\Q$dir\E\/nope\.profile'/, 'a missing profile in the list is fatal') ;

done_testing ;
