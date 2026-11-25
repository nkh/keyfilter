#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use File::Basename () ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $root     = "$FindBin::Bin/..";
my @examples = sort glob("$root/examples/[0-9][0-9]-*.sh") ;

cmp_ok(scalar @examples, '>=', 15, 'there are many examples') ;
ok(-x "$root/examples/run-all.sh", 'and a script that runs them all') ;
ok(-r "$root/examples/README.md", 'and an index') ;
ok(-l "$root/keyfilterctl" && readlink("$root/keyfilterctl") eq 'keyfilter', 'keyfilterctl is a link to keyfilter, so the examples work without installing') ;

for my $profile (glob("$root/examples/profiles/*.profile"))
	{
	ok(eval { KeyFilter::Profile::load($profile) ; 1 }, 'the sample profile ' . File::Basename::basename($profile) . ' loads') or diag $@ ;
	}

my $index = read_file("$root/examples/README.md") ;
my $sentinel = temp_dir() ;

for my $example (@examples)
	{
	my $name = File::Basename::basename($example) ;
	
	ok(-x $example, "$name is executable") ;
	like($index, qr/\Q$name\E/, "$name is in the index") ;
	like(read_file($example), qr/\A#!\/bin\/sh\n#/, "$name starts with a shell line and a comment that says what it shows") ;
	}

# every example runs, from another directory, with a home directory that must stay empty

for my $example (@examples)
	{
	my $name   = File::Basename::basename($example) ;
	my $output = qx{cd / && HOME=$sentinel TMPDIR=$sentinel timeout 120 $example 2>&1} ;
	
	is($? >> 8, 0, "$name succeeds") or diag $output ;
	like($output, qr/\nOK\n\z/, "$name ends with OK") ;
	unlike($output, qr/FAILED/, "$name has no failure") ;
	}

opendir(my $handle, "$sentinel") or die ;

my @left = grep { !/\A\.\.?\z/ } readdir $handle ;

closedir $handle ;

is_deeply(\@left, [], 'the examples leave nothing in the home directory of the user, nor in the temporary directory') ;

my $all = qx{cd / && HOME=$sentinel TMPDIR=$sentinel $root/examples/run-all.sh 2>&1} ;

is($? >> 8, 0, 'run-all.sh succeeds') ;
like($all, qr/\n\d+ examples, 0 failed\n\z/, 'and counts the examples') ;

done_testing ;
