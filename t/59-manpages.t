#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;
use lib "$FindBin::Bin/lib" ;
use KeyFilterTest ;

my $root = "$FindBin::Bin/.." ;
my $ctl_help = KeyFilter::Ctl::help_text() ;
my $help     = KeyFilter::CLI::help_text() ;

for my $page ('keyfilter', 'keyfilterctl')
	{
	my $file = "$root/man/$page.1" ;
	
	ok(-r $file, "man/$page.1 exists") ;
	
	my $text = read_file($file) ;
	
	like($text, qr/\A\.\\" /, 'it starts with a comment') ;
	like($text, qr/^\.TH \U$page\E 1 "[A-Z][a-z]+ \d{4}" "KeyFilter \Q$KeyFilter::CLI::VERSION\E" "User Commands"$/m, 'it has a title line with the section, the date and the version') ;
	is(scalar(() = $text =~ /^\.TH /mg), 1, 'with only one') ;
	
	for my $section ('NAME', 'SYNOPSIS', 'DESCRIPTION', 'OPTIONS', 'EXIT STATUS', 'EXAMPLES', 'AUTHOR', 'SEE ALSO')
		{
		like($text, qr/^\.SH \Q$section\E$/m, "section $section") ;
		}
	
	like($text, qr/^\.SH NAME\n\Q$page\E \\- .+\n/m, 'the name line is: name, dash, what it does') ;
	
	my $fill = () = $text =~ /^\.nf$/mg ;
	my $nofill = () = $text =~ /^\.fi$/mg ;
	
	is($fill, $nofill, 'every .nf has its .fi') ;
	
	my $rs = () = $text =~ /^\.RS$/mg ;
	my $re = () = $text =~ /^\.RE$/mg ;
	
	is($rs, $re, 'every .RS has its .RE') ;
	
	unlike($text, qr/^'/m, 'no line starts with an apostrophe') ;
	unlike($text, qr/ \-\-[a-z]/, 'dashes in options are written \\-') ;
	unlike($text, qr/[ \t]+$/m, 'no line ends with a space') ;
	
	SKIP:
		{
		skip 'no nroff', 3 unless system('nroff --version >/dev/null 2>&1') == 0 || system('which nroff >/dev/null 2>&1') == 0 ;
		
		my $warnings = qx{nroff -man -ww -z $file 2>&1} ;
		
		is($warnings, '', 'nroff has no warning') ;
		
		my $rendered = qx{nroff -man $file 2>/dev/null} ;
		
		$rendered =~ s/\e\[[0-9;]*m//g ;
		$rendered =~ s/.\x08//g ;
		
		like($rendered, qr/\Q\U$page\E\E\(1\)/, 'it is rendered with its title') ;
		like($rendered, qr/NAME\s+\Q$page\E\s+-\s+/, 'and its name line') ;
		}
	}

# what the program says is in the pages

my $page = read_file("$root/man/keyfilter.1") ;
my $page_text = $page =~ s/\\-/-/gr ;

my %seen ;

for my $option ($help =~ /(--[a-z-]+|(?<=\s)-h\b)/g)
	{
	next if $seen{$option}++ ;
	
	like($page_text, qr/\Q$option\E/, "keyfilter(1) documents $option") ;
	}

my $ctl_page = read_file("$root/man/keyfilterctl.1") =~ s/\\-/-/gr ;

for my $command ($ctl_help =~ /^  ([a-z]+)(?: |$)/mg)
	{
	like($ctl_page, qr/^\.(?:B|BI) \Q$command\E/m, "keyfilterctl(1) documents $command") ;
	}

like($ctl_page, qr/--pid/, 'and --pid') ;
like($page, qr/keyfilterctl/, 'keyfilter(1) refers to keyfilterctl') ;
like($page, qr/^\.BR keyfilterctl \(1\)/m, 'in its references') ;
like($ctl_page, qr/^\.BR keyfilter \(1\)/m, 'and keyfilterctl(1) to keyfilter') ;

for my $name ('Enter', 'Tab', 'Esc', 'Space', 'Backspace', 'Up', 'Down', 'Left', 'Right', 'Home', 'End', 'Insert', 'Delete', 'PgUp', 'PgDn', 'F1', 'F12', 'C-', 'M-', 'S-')
	{
	like($page_text, qr/\Q$name\E/, "the key $name is documented") ;
	}

for my $thing ('keyfilter_runtime', 'startup-delay', 'send-startup', 'include', '65536', '50 milliseconds', '~/.config/keyfilter', 'sockets', 'EXIT STATUS', '255')
	{
	like($page_text . $ctl_page, qr/\Q$thing\E/, "the pages tell about $thing") ;
	}

done_testing ;
