#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 44 ;
use Test::RDF;
use Test::WWW::Mechanize::PSGI;

my $tester = do "script/linked_data.psgi";

BAIL_OUT("The application is not running") unless ($tester);

use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

{
    note "Get /foo, no redirects";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    like($res->header('Location'), qr|/foo/data$|, "Location is OK");
}


foreach my $accept_header (('text/html',
			    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
			    'text/html, application/xml;q=0.9, application/xhtml+xml, image/png, image/jpeg, image/gif, image/x-xbitmap, */*;q=0.1',
			    'application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
			    'image/jpeg, application/x-ms-application, image/gif, application/xaml+xml, image/pjpeg, application/x-ms-xbap, application/x-shockwave-flash, application/msword, */*')) {
    note "Get /foo, no redirects, ask for $accept_header";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => $accept_header);
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    is($res->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
}


{
    note "Get /foo/page, no redirects";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    my $res = $mech->get("/foo/page");
    is($mech->status, 301, "Returns 301");
    is($res->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
}

{
    note "Get /foo, no redirects, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'application/rdf+xml');
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    like($res->header('Location'), qr|/foo/data$|, "Location is OK");
}

{
    note "Get /foo, no redirects, use Tabulators Accept header";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'application/rdf+xml, application/xhtml+xml;q=0.3, text/xml;q=0.2, application/xml;q=0.2, text/html;q=0.3, text/plain;q=0.1, text/n3, text/rdf+n3;q=0.5, application/x-turtle;q=0.2, text/turtle;q=1');
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    like($res->header('Location'), qr|/foo/data$|, "Location is OK");
}

{
    note "Get /dahut, no redirects, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'application/rdf+xml');
    my $res = $mech->get("/dahut");
    is($mech->status, 404, "Returns 404");
}


my $rxparser = RDF::Trine::Parser->new( 'rdfxml' );
my $base_uri = 'http://localhost/';

{
    note "Get /foo, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/rdf+xml');
    $mech->get_ok("/foo");
    is($mech->ct, 'application/rdf+xml', "Correct content-type");
    like($mech->uri, qr|/foo/data$|, "Location is OK");
    my $model = RDF::Trine::Model->temporary_model;
    is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
    $rxparser->parse_into_model( $base_uri, $mech->content, $model );
    has_subject($base_uri . 'foo', $model, "Subject URI in content");
    has_literal('This is a test', 'en', undef, $model, "Test phrase in content");
}

{
    note "Get /foo, ask for Turtle";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/turtle');
    $mech->get_ok("/foo");
    is($mech->ct, 'application/turtle', "Correct content-type");
    like($mech->uri, qr|/foo/data$|, "Location is OK");
    my $model = RDF::Trine::Model->temporary_model;
    is_valid_rdf($mech->content, 'turtle', 'Returns valid Turtle');
    my $parser = RDF::Trine::Parser->new( 'turtle' );
    $parser->parse_into_model( $base_uri, $mech->content, $model );
    has_subject($base_uri . 'foo', $model, "Subject URI in content");
    has_literal('This is a test', 'en', undef, $model, "Test phrase in content");
}

{
    note "Get /bar/baz/bing, no redirects, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'application/rdf+xml');
    my $res = $mech->get("/bar/baz/bing");
    is($mech->status, 303, "Returns 303");
    like($res->header('Location'), qr|/bar/baz/bing/data$|, "Location is OK");
}


{
    note "Get /bar/baz/bing";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'text/html');
    $mech->get_ok("/bar/baz/bing");
    is($mech->ct, 'text/html', "Correct content-type");
    like($mech->uri, qr|/bar/baz/bing/page$|, "Location is OK");
    $mech->title_is('Testing with longer URI.', "Title is correct");
}


{
    note "Get /bar/baz/bing, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/rdf+xml');
    $mech->get_ok("/bar/baz/bing");
    is($mech->ct, 'application/rdf+xml', "Correct content-type");
    like($mech->uri, qr|/bar/baz/bing/data$|, "Location is OK");
    my $model = RDF::Trine::Model->temporary_model;
    is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
    $rxparser->parse_into_model( $base_uri, $mech->content, $model );
    has_subject($base_uri . 'bar/baz/bing', $model, "Subject URI in content");
    has_literal('Testing with longer URI.', 'en', undef, $model, "Test phrase in content");
}



TODO: {
    local $TODO = "We really should return 406 if no acceptable version is there, shouldn't we?";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/foobar');
    my $res = $mech->get("/foo/data");
    is($mech->status, 406, "Returns 406");
}


done_testing();
