#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $root   = "$FindBin::Bin/.." ;
my $readme = read_file("$root/README.md") ;

sub shell_words
{
my ($line) = @_ ;

my @words ;
my $word    = '' ;
my $started = 0 ;

while (length $line)
	{
	if ($line =~ s/\A'([^']*)'//)
		{
		$word .= $1 ;
		$started = 1 ;
		}
	elsif ($line =~ s/\A"((?:[^"\\]|\\.)*)"//)
		{
		$word .= $1 =~ s/\\(.)/$1/gr ;
		$started = 1 ;
		}
	elsif ($line =~ s/\A\\(.)//)
		{
		$word .= $1 ;
		$started = 1 ;
		}
	elsif ($line =~ s/\A\s+//)
		{
		push @words, $word if $started ;
		
		$word    = '' ;
		$started = 0 ;
		}
	else
		{
		$line =~ s/\A(.)//s ;
		
		$word .= $1 ;
		$started = 1 ;
		}
	}

push @words, $word if $started ;

return @words ;
}

# -----------------------------------------------------------------------------

# the command lines of the README, the continued ones in one

my @lines ;
my $pending = '' ;

for my $line (split /\n/, $readme)
	{
	my $text ;
	
	if ($line =~ /\A    (\S.*)\z/)
		{
		$text = $1 ;
		}
	elsif (length $pending && $line =~ /\A\s+(\S.*)\z/)
		{
		$text = $1 ;
		}
	else
		{
		next ;
		}
	
	$pending .= ($pending ? ' ' : '') . ($text =~ s/\\\z//r) ;
	
	if ($text !~ /\\\z/)
		{
		push @lines, $pending ;
		
		$pending = '' ;
		}
	}

my @keyfilter = grep { /\A\.\/keyfilter / } @lines ;
my @control   = grep { /\A\.\/keyfilterctl / } @lines ;

cmp_ok(scalar @keyfilter, '>=', 10, 'the README has command lines of keyfilter') ;
cmp_ok(scalar @control, '>=', 6, 'and of keyfilterctl') ;

my $home = temp_dir() ;

for my $line (@keyfilter)
	{
	my (undef, @words) = shell_words($line) ;
	
	my $options = eval { KeyFilter::CLI::parse_arguments(@words) ; } ;
	
	ok($options, "keyfilter accepts: $line") or diag $@ ;
	
	for my $profile (@{$options->{profiles} // []})
		{
		next unless $profile =~ m{/} ;
		
		ok(-r "$root/$profile", "the profile $profile of the README exists") ;
		}
	}

my %by_name = map { /\A\Q.\/keyfilterctl\E (?:--pid \d+ )?(\S+)/ ? ($1 => 1) : () } @control ;

for my $command (qw(ls send toggle block unblock map))
	{
	ok($by_name{$command}, "the README shows keyfilterctl $command") ;
	}

for my $line (@control)
	{
	my (undef, @words) = shell_words($line) ;
	
	shift @words, shift @words if $words[0] eq '--pid' ;
	
	my ($command, @arguments) = @words ;
	
	if ($command eq 'ls')
		{
		pass("keyfilterctl accepts: $line") ;
		
		next ;
		}
	
	my $text = join(' ', $command, @arguments) ;
	my $parsed = eval { KeyFilter::Control::parse_line($text) ; } ;
	
	ok($parsed, "keyfilterctl accepts: $line") or diag $@ ;
	}

# the README speaks of files that exist

for my $path ('examples/profiles', 'man/keyfilter.1', 'man/keyfilterctl.1', 'examples', 'KeyFilter-Requirements.md', 'KeyFilter-Implementation-Roadmap.md', 'examples/run-all.sh')
	{
	ok(-e "$root/$path", "the README mentions $path, which exists") if $readme =~ /\Q$path\E/ ;
	}

for my $path ($readme =~ /`(examples\/profiles\/[a-z]+\.profile)`/g)
	{
	ok(-r "$root/$path", "$path exists") ;
	}

like($readme, qr/Nothing has to be installed/, 'the README says nothing has to be installed') ;
ok(-x "$root/keyfilter" && -l "$root/keyfilterctl", 'the commands of the README are there to run') ;

# the commands that can run, run

my $F5 = qx{printf '\\033[15~' | (sleep 1 ; cat) | HOME=$home $root/keyfilter --map F5='git status\\n' -- sh -c 'stty raw -echo ; head -c 11'} ;

is($F5, "git status\n", "the first example of the issue, ./keyfilter --map F5='git status\\n' -- bash, works") ;

like(qx{$root/keyfilter --help}, qr/^Usage: keyfilter/, './keyfilter --help works') ;
is(qx{$root/keyfilterctl --help 2>&1} =~ s/\n.*//sr, 'Usage: keyfilterctl [--pid PID] command [arguments]', './keyfilterctl --help works') ;

done_testing ;
