#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use Time::HiRes () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $dir     = temp_dir() ;
my $counter = 0 ;
my @writers ;

sub startup_of
{
my (@files) = @_ ;

return KeyFilter::Startup->from_profiles(KeyFilter::Profile::load_profiles(@files)) ;
}

# -----------------------------------------------------------------------------

sub pump_until
{
my ($pty, $condition, $timeout) = @_ ;

my $deadline = Time::HiRes::time() + ($timeout // 20) ;

while (Time::HiRes::time() < $deadline)
	{
	return 1 if $condition->() ;
	
	$pty->pump(0.02) ;
	}

return $condition->() ? 1 : 0 ;
}

# -----------------------------------------------------------------------------

sub collector
{
my (%options) = @_ ;

my $name = 'case' . ++$counter ;

my ($input, $writer) = pipe_pair() ;

push @writers, $writer ;

my $before = $options{before} // '' ;
my $pty    = start_engine({ input => $input, startup => $options{startup} }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/$name.ready ; $before head -c $options{bytes} > $dir/$name.out") ;

die "the child is not ready\n" unless wait_for_file("$dir/$name.ready") ;

return { pty => $pty, writer => $writer, out => "$dir/$name.out" } ;
}

# -----------------------------------------------------------------------------

# one profile

write_file("$dir/one.profile", "# first\n", "send-startup a\n", "\n", "block x\n", "send-startup b\n", "map c=d\n", "send-startup c\n") ;

is_deeply([ startup_of("$dir/one.profile")->actions ], ['a', 'b', 'c'], 'the actions of a profile are in the order of its lines') ;

write_file("$dir/delays.profile", "send-startup a\n", "startup-delay 100\n", "send-startup b\n", "startup-delay 300\n", "send-startup c\n") ;

is(startup_of("$dir/delays.profile")->delay_ms, 300, 'the last delay of a profile wins') ;
is_deeply([ startup_of("$dir/delays.profile")->actions ], ['a', 'b', 'c'], 'and the delays do not take part in the order of the actions') ;

write_file("$dir/delay-last.profile", "send-startup a\n", "send-startup b\n", "startup-delay 250\n") ;

is(startup_of("$dir/delay-last.profile")->delay_ms, 250, 'a delay declared after the actions still applies to them') ;

write_file("$dir/no-startup.profile", "block a\n", "map b=c\n", "toggle x\n", "send abc\n") ;

my $none = startup_of("$dir/no-startup.profile") ;

is_deeply([ $none->actions ], [], 'rules and other commands are not startup actions') ;
is($none->delay_ms, 0, 'and give no delay') ;

# several profiles

write_file("$dir/p1.profile", "send-startup 1a\n", "send-startup 1b\n", "startup-delay 100\n") ;
write_file("$dir/p2.profile", "send-startup 2a\n", "startup-delay 200\n", "send-startup 2b\n") ;
write_file("$dir/p3.profile", "send-startup 3a\n") ;

is_deeply([ startup_of("$dir/p1.profile", "$dir/p2.profile", "$dir/p3.profile")->actions ], ['1a', '1b', '2a', '2b', '3a'], 'the actions of several profiles are in the order of the profiles') ;
is_deeply([ startup_of("$dir/p3.profile", "$dir/p2.profile", "$dir/p1.profile")->actions ], ['3a', '2a', '2b', '1a', '1b'], 'whatever that order is') ;
is(startup_of("$dir/p1.profile", "$dir/p2.profile")->delay_ms, 200, 'the delay of the last profile that has one wins') ;
is(startup_of("$dir/p2.profile", "$dir/p1.profile")->delay_ms, 100, 'in either order') ;
is(startup_of("$dir/p1.profile", "$dir/p2.profile", "$dir/p3.profile")->delay_ms, 200, 'a later profile without a delay does not reset it') ;

write_file("$dir/reset.profile", "startup-delay 0\n") ;

is(startup_of("$dir/p1.profile", "$dir/reset.profile")->delay_ms, 0, 'a later zero delay does reset it') ;

is_deeply([ KeyFilter::Startup->from_profiles()->actions ], [], 'no profile, no action') ;
is(KeyFilter::Startup->from_profiles()->delay_ms, 0, 'and no delay') ;

isa_ok(startup_of("$dir/p1.profile"), 'KeyFilter::Startup') ;

like(failure_of(sub { KeyFilter::Startup->from_profiles('p1') ; }), qr/not a profile/, 'a name is not a profile') ;
like(failure_of(sub { KeyFilter::Startup->from_profiles(undef) ; }), qr/not a profile/, 'undef is not a profile') ;
like(failure_of(sub { KeyFilter::Startup->from_profiles({}) ; }), qr/not a profile/, 'a hash is not a profile') ;

# includes

write_file("$dir/inc-b.profile", "send-startup B1\n", "send-startup B2\n") ;
write_file("$dir/inc-main.profile", "send-startup A\n", "include inc-b.profile\n", "send-startup C\n") ;

is_deeply([ startup_of("$dir/inc-main.profile")->actions ], ['A', 'B1', 'B2', 'C'], 'an included file puts its actions where its include is') ;

write_file("$dir/deep-c.profile", "send-startup C1\n") ;
write_file("$dir/deep-b.profile", "send-startup B1\n", "include deep-c.profile\n", "send-startup B2\n") ;
write_file("$dir/deep-a.profile", "send-startup A1\n", "include deep-b.profile\n", "send-startup A2\n") ;

is_deeply([ startup_of("$dir/deep-a.profile")->actions ], ['A1', 'B1', 'C1', 'B2', 'A2'], 'includes inside includes keep the order') ;

write_file("$dir/twice-main.profile", "include inc-b.profile\n", "send-startup X\n", "include inc-b.profile\n") ;

is_deeply([ startup_of("$dir/twice-main.profile")->actions ], ['B1', 'B2', 'X'], 'a file included twice gives its actions once, at the first include') ;

write_file("$dir/inc-delay.profile", "startup-delay 900\n", "send-startup D\n") ;
write_file("$dir/delay-main.profile", "startup-delay 100\n", "include inc-delay.profile\n", "send-startup E\n") ;

is(startup_of("$dir/delay-main.profile")->delay_ms, 900, 'a delay in an included file counts where the include is') ;

write_file("$dir/delay-after.profile", "include inc-delay.profile\n", "startup-delay 50\n") ;

is(startup_of("$dir/delay-after.profile")->delay_ms, 50, 'and a later delay wins over it') ;

write_file("$dir/shared.profile", "send-startup S\n") ;
write_file("$dir/s1.profile", "send-startup 1\n", "include shared.profile\n") ;
write_file("$dir/s2.profile", "send-startup 2\n", "include shared.profile\n") ;

is_deeply([ startup_of("$dir/s1.profile", "$dir/s2.profile")->actions ], ['1', 'S', '2'], 'a file included by two profiles is loaded once for both') ;

# what the user types and what the startup sends

my $case = collector(bytes => 5, startup => startup_of("$dir/p3.profile")) ;

is(length(startup_of("$dir/p3.profile")->text), 2, 'the profile sends two bytes') ;

write_file("$dir/typed.profile", "startup-delay 400\n", "send-startup SS\n") ;

$case = collector(bytes => 6, startup => startup_of("$dir/typed.profile")) ;

syswrite($case->{writer}, 'U1') ;

pump_until($case->{pty}, sub { $case->{pty}->input_eof || -s "$dir/never" || $case->{pty}->pending_input == 0 && Time::HiRes::time() > 0 ; }, 0.1) ;

$case->{pty}->pump(0.05) for 1 .. 4 ;

is($case->{pty}->startup_fired, 0, 'the user typed before the startup') ;

pump_until($case->{pty}, sub { $case->{pty}->startup_fired ; }) ;

syswrite($case->{writer}, 'U2') ;

pump_until($case->{pty}, sub { !$case->{pty}->is_running ; }) ;

is(read_file($case->{out}), 'U1SSU2', 'what is typed before the delay comes first, what is typed after comes after the text of the startup') ;

write_file("$dir/slowtyped.profile", "startup-delay 300\n", "send-startup END\n") ;

my ($slow_input, $slow_writer) = pipe_pair() ;

push @writers, $slow_writer ;

my $slow = start_engine({ input => $slow_input, startup => startup_of("$dir/slowtyped.profile") }, 'sh', '-c', "stty raw -echo ; echo ready > $dir/slowtyped.ready ; sleep 1.2 ; head -c 60003 > $dir/slowtyped.out") ;

wait_for_file("$dir/slowtyped.ready") ;

syswrite($slow_writer, 'u' x 60000) ;

pump_until($slow, sub { $slow->startup_fired ; }) ;

cmp_ok($slow->pending_input, '>', 0, 'a lot of typed input is still pending when the startup fires') ;

pump_until($slow, sub { !$slow->pending_input ; }, 30) ;
$slow->wait_exit ;

is(read_file("$dir/slowtyped.out"), ('u' x 60000) . 'END', 'and the text of the startup comes after all of it') ;

# a whole run from files

write_file("$dir/run-b.profile", "send-startup two\n") ;
write_file("$dir/run-a.profile", "startup-delay 150\n", "send-startup one\n", "include run-b.profile\n", "send-startup three\n") ;
write_file("$dir/run-c.profile", "send-startup four\n") ;

my $run = engine_process({ startup => startup_of("$dir/run-a.profile", "$dir/run-c.profile") }, 'sh', '-c', 'stty raw -echo ; echo ready ; head -c 15') ;

is($run->read_all, "ready\nonetwothreefour", 'profiles, includes and startup together give the text in order to the child') ;
is($run->finish, 0, 'and the run ends') ;

done_testing ;
