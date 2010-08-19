#!/usr/bin/perl

use FindBin qw($Bin);
use HTTP::Headers;

use strict;
use Test::More tests => 37;
use Test::Exception;
#use Test::NoWarnings;



my $file = $Bin . '/data/basic.ttl';

BEGIN {
    use_ok('RDF::LinkedData');
    use_ok('RDF::Helper::Properties');
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


{
    diag "Get /foo";
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 303, "Returns 303");
    like($response->header('Location'), qr|/foo/data$|, "Location is OK");
}

{
    diag "Get /foo, ask for text/html";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'text/html'));
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 303, "Returns 303");
    is($response->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
}

TODO: {
    local $TODO = 'Firefox default Accept header gives Turtle';
    diag "Get /foo, use Firefox' default Accept header";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'));
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 303, "Returns 303");
    is($response->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
}

{
    diag "Get /foo, ask for RDF/XML";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'application/rdf+xml'));
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 303, "Returns 303");
    like($response->header('Location'), qr|/foo/data$|, "Location is OK");
}


{
    diag "Get /foo, ask for Turtle";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'application/turtle'));
    my $response = $ld->response("/foo");
    like($response->header('Location'), qr|/foo/data$|, "Location is OK");
}


{
    diag "Get /dahut, ask for RDF/XML";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'application/rdf+xml'));
    my $response = $ld->response('/dahut');
    isa_ok($response, 'Plack::Response');
    is($response->status, 404, "Returns 404");
}


{
    diag "Get /foo/page";
    $ld->type('page');
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 301, "Returns 301");
    is($response->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
}

{
    diag "Get /bar/baz/bing";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'text/html'));
    my $response = $ld->response ("/bar/baz/bing");
    isa_ok($response, 'Plack::Response');
    is($response->status, 303, "Returns 303");
    like($response->header('Location'), qr|/bar/baz/bing/page$|, "Location is OK");
}

{
    diag "Get /bar/baz/bing/page";
    $ld->type('page');
    my $response = $ld->response ("/bar/baz/bing");
    isa_ok($response, 'Plack::Response');
    is($response->status, 200, "Returns 200");
    is($response->content_type, 'text/html', 'Returns HTML');
    like($response->body, qr|Testing with longer URI\.|, "Test phrase in content");
}


{
    diag "Get /bar/baz/bing, ask for RDF/XML";
    $ld->headers_in(HTTP::Headers->new('Accept' => 'application/rdf+xml'));
    my $response = $ld->response("/bar/baz/bing");
    is($response->status, 303, "Returns 303");
    like($response->header('Location'), qr|/bar/baz/bing/data$|, "Location is OK");
}




{
    diag "Get /foo/data";
    $ld->type('data');
    my $response = $ld->response('/foo');
    isa_ok($response, 'Plack::Response');
    is($response->status, 200, "Returns 200");
    like($response->body, qr|This is a test|, "Test phrase in content");

}

