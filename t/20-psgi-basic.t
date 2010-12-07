#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 32 ;
use Test::WWW::Mechanize::PSGI;

my $tester = do "script/linked_data.psgi";

use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

{
    note "Get /foo, no redirects";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    like($res->header('Location'), qr|/foo/data$|, "Location is OK");
}

{
    note "Get /foo, no redirects, ask for text/html";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'text/html');
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

TODO:{
  local $TODO = "Users should see a page, with normal FF";
    note "Get /foo, no redirects, use FFs Accept header";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester, requests_redirectable => []);
    $mech->default_header('Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    my $res = $mech->get("/foo");
    is($mech->status, 303, "Returns 303");
    is($res->header('Location'), 'http://en.wikipedia.org/wiki/Foo', "Location is Wikipedia page");
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

{
    note "Get /foo, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/rdf+xml');
    $mech->get_ok("/foo");
    is($mech->ct, 'application/rdf+xml', "Correct content-type");
    like($mech->uri, qr|/foo/data$|, "Location is OK");
    $mech->content_contains('This is a test', "Test phrase in content");
}

{
    note "Get /foo, ask for Turtle";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/turtle');
    $mech->get_ok("/foo");
    is($mech->ct, 'application/turtle', "Correct content-type");
    like($mech->uri, qr|/foo/data$|, "Location is OK");
    $mech->content_contains('This is a test', "Test phrase in content");
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
    $mech->content_contains('Testing with longer URI.', "Test phrase in content");
}



TODO: {
    local $TODO = "We really should return 406 if no acceptable version is there, shouldn't we?";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
    $mech->default_header('Accept' => 'application/foobar');
    my $res = $mech->get("/foo/data");
    is($mech->status, 406, "Returns 406");
}


done_testing();
