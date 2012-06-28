#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use Test::WWW::Mechanize::PSGI;
use Module::Load::Conditional qw[check_install];
use RDF::Trine::Namespace qw(rdf);;


unless (defined(check_install( module => 'RDF::Endpoint', version => 0.03))) {
  plan skip_all => 'You need RDF::Endpoint for this test'
}

unless (defined(check_install( module => 'RDF::Generator::Void', version => 0.02))) {
  plan skip_all => 'You need RDF::Generator::Void for this test'
}




$ENV{'RDF_LINKEDDATA_CONFIG_LOCAL_SUFFIX'} = 'void';

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


my $rxparser = RDF::Trine::Parser->new( 'rdfxml' );
my $base_uri = 'http://localhost/';



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
  TODO: {
		 local $TODO = 'Hypermedia now only links to void';
		 hasnt_uri('http://rdfs.org/ns/void#sparqlEndpoint', $model, 'SPARQL endpoint link in data');
		 hasnt_uri($base_uri . 'sparql', $model, 'SPARQL endpoint in data');
	 }
}

{
	note "Get the base_uri with the VoID";
	my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
	$mech->default_header('Accept' => 'application/rdf+xml');
	$mech->get_ok($base_uri);
	is($mech->ct, 'application/rdf+xml', "Correct content-type");
	my $model = RDF::Trine::Model->temporary_model;
	is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	$rxparser->parse_into_model( $base_uri, $mech->content, $model );
	has_subject($base_uri . '#dataset-0', $model, "Subject URI in content");
	pattern_target($model);
	my $void = RDF::Trine::Namespace->new('http://rdfs.org/ns/void#');
	my $xsd  = RDF::Trine::Namespace->new('http://www.w3.org/2001/XMLSchema#');
	pattern_ok(
				  statement(
								iri($base_uri . '#dataset-0'),
								$void->triples,
								literal(3, undef, $xsd->integer)
							  ),
				  statement(
								iri($base_uri . '#dataset-0'),
								$void->sparqlEndpoint,
								iri($base_uri . 'sparql'),
							  ),
				  statement(
								iri($base_uri . '#dataset-0'),
								$rdf->type,
								$void->Dataset
							  ),
				  'Common statements are there');
}



done_testing();
