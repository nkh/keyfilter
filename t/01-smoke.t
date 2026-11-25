#!/usr/bin/env perl

use strict ;
use warnings ;
use Test::More ;
use FindBin ;

my $script = "$FindBin::Bin/../keyfilter" ;

ok(-f $script, 'keyfilter exists') ;
ok(-x $script, 'keyfilter is executable') ;

my $output = qx{$^X -c '$script' 2>&1} ;

is($?, 0, 'keyfilter compiles') or diag $output ;

$output = qx{$^X '$script' 2>&1 </dev/null} ;

isnt($?, 0, 'keyfilter without arguments fails') ;
like($output, qr/Usage/, 'keyfilter without arguments prints usage') ;

done_testing ;
