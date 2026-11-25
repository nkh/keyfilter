#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my @cases =
	(
	['startup-delay 500', { cmd => 'startup-delay', ms => 500 }],
	['startup-delay 2000', { cmd => 'startup-delay', ms => 2000 }],
	['startup-delay 0', { cmd => 'startup-delay', ms => 0 }],
	['startup-delay 0500', { cmd => 'startup-delay', ms => 500 }],
	['startup-delay 500  ', { cmd => 'startup-delay', ms => 500 }],
	['startup-delay 500 # half a second', { cmd => 'startup-delay', ms => 500 }],
	['send-startup source env.sh\n', { cmd => 'send-startup', text => "source env.sh\n" }],
	['send-startup make\n', { cmd => 'send-startup', text => "make\n" }],
	['send-startup <<Enter>>', { cmd => 'send-startup', text => "\r" }],
	['send-startup abc<<Enter>><<C-a>>', { cmd => 'send-startup', text => "abc\r\x01" }],
	['send-startup  trailing space ', { cmd => 'send-startup', text => 'trailing space ' }],
	['send-startup \x20leading', { cmd => 'send-startup', text => ' leading' }],
	) ;

for my $case (@cases)
	{
	my ($line, $expected) = @$case ;
	
	is_deeply(scalar KeyFilter::Command::parse_command($line), $expected, $line) ;
	}

my @errors =
	(
	['startup-delay', qr/invalid duration ''/],
	['startup-delay 500ms', qr/invalid duration '500ms'/],
	['startup-delay 500 ms', qr/invalid duration '500 ms'/],
	['startup-delay 1.5', qr/invalid duration '1.5'/],
	['startup-delay 2s', qr/invalid duration '2s'/],
	['startup-delay -1', qr/invalid duration '-1'/],
	['startup-delay ms', qr/invalid duration 'ms'/],
	['send-startup', qr/send-startup requires text/],
	['send-startup a<<bogus>>', qr/unknown key specification 'bogus'/],
	['send-startup a\q', qr/unknown escape/],
	) ;

for my $case (@errors)
	{
	my ($line, $pattern) = @$case ;
	
	like(failure_of(sub { KeyFilter::Command::parse_command($line) ; }), $pattern, "error for '$line'") ;
	}

done_testing ;
