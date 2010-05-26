#!/usr/bin/perl

use FindBin qw($Bin);
use HTTP::Headers;

use strict;
use Test::More tests => 23;
use Test::Exception;
use Test::NoWarnings;

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
is($ld->count, 3, "There are 3 triples in model");
is_deeply($ld->model, $model, "The model is still the model");

is($ld->base, $base_uri, "The base is still the base");

my $node = $ld->my_node('/foo');

isa_ok($node, 'RDF::Trine::Node::Resource');

is($node->uri_value, 'http://localhost:3000/foo', "URI is still there");

my $preds = RDF::LinkedData::Predicates->new($model);

is($preds->title($node), 'This is a test', "Correct title");

{
    my $h = HTTP::Headers->new(Accept	=> 'application/rdf+xml');
    my $ldh = $ld;
    $ldh->headers_in($h);
    my $content = $ldh->content($node, 'data');

    is($content->{content_type}, 'application/rdf+xml', "RDF/XML content type");
}

{
    my $h = HTTP::Headers->new(Accept	=> 'application/turtle');
    my $ldh = $ld;
    $ldh->headers_in($h); 
    my $content = $ldh->content($node, 'data');
    is($content->{content_type}, 'application/turtle', "Turtle content type");
    is($content->{body}, '<http://localhost:3000/foo> <http://xmlns.com/foaf/0.1/page> <http://en.wikipedia.org/wiki/Foo> ;' . "\n\t" . '<http://www.w3.org/2000/01/rdf-schema#label> "This is a test"@en .' . "\n", 'Ntriples serialized correctly');
}

my $barnode = $ld->my_node('/bar/baz/bing');
isa_ok($node, 'RDF::Trine::Node::Resource');

is($barnode->uri_value, 'http://localhost:3000/bar/baz/bing', "'Bar' URI is still there");

{
    my $h = HTTP::Headers->new(Accept	=> 'text/html');
    my $ldh = $ld;
    $ldh->headers_in($h); 
    TODO: {
          local $TODO = "What should really be done with a text/html request for data?";
          my $content;
          lives_ok{ $content = $ldh->content($barnode, 'data') }, "Should give us a way to give a 406";
          is($content->{content_type}, 'application/rdf+xml', "Data type overrides and gives RDF/XML"); # TODO: is this correct?
    }
    {
        my $content = $ldh->content($barnode, 'page');
        is($content->{content_type}, 'text/html', "Page gives HTML");
    }
}

is($preds->page($node), 'http://en.wikipedia.org/wiki/Foo', "/foo has a foaf:page at Wikipedia");

is($preds->page($barnode), 'http://localhost:3000/bar/baz/bing/page', "/bar/baz/bing has default page");

