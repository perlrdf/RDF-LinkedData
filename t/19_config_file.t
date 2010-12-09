#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2 ;

use Test::JSON;

ok(open(CONFIG, '<rdf_linkeddata.json'), 'Test config file opened OK');
my $json = join("\n", <CONFIG>);
close CONFIG;
is_valid_json ($json, 'File contains valid JSON');


done_testing();
