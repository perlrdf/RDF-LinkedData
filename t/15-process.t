#!/usr/bin/perl

use FindBin qw($Bin);
use HTTP::Headers;

use strict;
use Test::More;# tests => 22;
use Test::Exception;
#use Test::NoWarnings;



my $file = $Bin . '/data/basic.ttl';

BEGIN {
    use_ok('RDF::LinkedData');
    use_ok('RDF::LinkedData::Predicates');
    use_ok('RDF::Trine::Parser');
    use_ok('RDF::Trine::Model');
}



my $parser     = RDF::Trine::Parser->new( 'turtle' );
my $model = RDF::Trine::Model->temporary_model;
my $base_uri = 'http://localhost:3000';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");

my $ld = RDF::LinkedData->new(model => $model, base=>$base_uri);

isa_ok($ld, 'RDF::LinkedData');
ok($ld->count > 0, "There are triples in the model");

diag "Get /foo";

ok($ld->process('/foo'), 'Processed URI');
isa_ok($ld->response, 'HTTP::Response');
is($ld->response->code, 303, "Returns 303");
is($ld->response->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");

diag "Get /foo/page";
$ld->type('page');
ok($ld->process('/foo'), 'Processed URI');
isa_ok($ld->response, 'HTTP::Response');
is($ld->response->code, 301, "Returns 301");
is($ld->response->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");

diag "Get /foo/data";
$ld->type('data');
ok($ld->process('/foo'), 'Processed URI');
isa_ok($ld->response, 'HTTP::Response');
is($ld->response->code, 303, "Returns 303");
like($ld->response->header('Location'), qr|/foo/data$|, "Location is OK");


