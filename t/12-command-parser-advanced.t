#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['toggle gaming', { cmd => 'toggle', profile => 'gaming' }],
	['  toggle   gaming  ', { cmd => 'toggle', profile => 'gaming' }],
	['include common.profile', { cmd => 'include', file => 'common.profile' }],
	['include ../shared/common.profile', { cmd => 'include', file => '../shared/common.profile' }],
	['include /etc/keyfilter/common.profile  ', { cmd => 'include', file => '/etc/keyfilter/common.profile' }],
	['include my file.profile', { cmd => 'include', file => 'my file.profile' }],
	['profile vim', { cmd => 'profile', profile => 'vim' }],
	['profile ./local.profile', { cmd => 'profile', profile => './local.profile' }],
	['profile ../test.profile', { cmd => 'profile', profile => '../test.profile' }],
	["profile vim\n", { cmd => 'profile', profile => 'vim' }],
	) ;

for my $case (@cases)
	{
	my ($line, $expected) = @$case ;
	
	is_deeply(scalar KeyFilter::Command::parse_command($line), $expected, $line) ;
	}

my @errors =
	(
	['toggle', qr/toggle requires an argument/],
	['toggle   ', qr/toggle requires an argument/],
	['include', qr/include requires an argument/],
	['profile', qr/profile requires an argument/],
	['Toggle gaming', qr/unknown command 'Toggle'/],
	) ;

for my $case (@errors)
	{
	my ($line, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Command::parse_command($line) ; }), $pattern, "error for '$line'") ;
	}

done_testing ;
