#!/usr/bin/perl

use RDF::LinkedData;
use Plack::Request;
use RDF::Trine;

$main::linked_data = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    unless ($req->method eq 'GET') {
        return [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ];
    }

    my $parser = RDF::Trine::Parser->new( 'turtle' );
    my $model = RDF::Trine::Model->temporary_model;
    my $base_uri = 'http://localhost:5000';
    $parser->parse_file_into_model( $base_uri, 't/data/basic.ttl', $model );
    my $ld = RDF::LinkedData->new(model => $model, base=>$base_uri);
    my $uri = $req->path_info;
    warn $uri;
    if ($req->path_info =~ m!^(.+?)/?(page|data)$!) {
        $uri = $1;
        $ld->type($2);
    }
    $ld->headers_in($req->headers);
    return $ld->response($uri)->finalize;
}
