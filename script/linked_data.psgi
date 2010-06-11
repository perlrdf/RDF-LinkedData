#!/usr/bin/perl

use RDF::LinkedData;
use Plack::Request;
use RDF::Trine;
use Config::Any;

$main::linked_data = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    unless ($req->method eq 'GET') {
        return [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ];
    }

    my $config = Config::Any->load_files({files => \@filepaths, ... });

    my $ld = RDF::LinkedData->new($config->{store}, $config->{base});
    my $uri = $req->path_info;
    warn $uri;
    if ($req->path_info =~ m!^(.+?)/?(page|data)$!) {
        $uri = $1;
        $ld->type($2);
    }
    $ld->headers_in($req->headers);
    return $ld->response($uri)->finalize;
}
