#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use Test::WWW::Mechanize::PSGI;
use Module::Load::Conditional qw[check_install];
use RDF::Trine::Namespace qw(rdf);




unless (defined(check_install( module => 'RDF::ACL', version => 0.1))) {
	plan skip_all => 'You need RDF::ACL for this test'
}


$ENV{'RDF_LINKEDDATA_CONFIG_LOCAL_SUFFIX'} = 'acl';

my $tester = do "script/linked_data.psgi";

BAIL_OUT("The application is not running") unless ($tester);

use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};




my $rxparser = RDF::Trine::Parser->new( 'rdfxml' );
my $base_uri = 'http://localhost/';

my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);


{
	note 'Write operations without authentication';
	$mech->post("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle', 
													Content => "<$base_uri/bar/baz/bing> <http://example.org/error> \"No merged triple\"\@en" });
	is($mech->status, 401, "Posting returns 401");
	$mech->put("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle',
												  Content => "<$base_uri/bar/baz/bing> <http://example.org/error> \"No merged triple\"\@en" });
	is($mech->status, 401, "Putting returns 401");

	ok($mech->credentials('testuser', 'sikrit' ), 'Setting credentials (cannot really fail...)');

	note "Get /bar/baz/bing, ask for RDF/XML";
	$mech->default_header('Accept' => 'application/rdf+xml');
	$mech->get_ok("/bar/baz/bing");
	is($mech->ct, 'application/rdf+xml', "Correct content-type");
	like($mech->uri, qr|/bar/baz/bing/data$|, "Location is OK");
	is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	my $model = return_model($mech->content, $rxparser);
	has_subject($base_uri . 'bar/baz/bing', $model, "Subject URI in content");
	has_literal('Testing with longer URI.', 'en', undef, $model, "Test phrase in content");
	hasnt_uri('http://rdfs.org/ns/void#sparqlEndpoint', $model, 'No SPARQL endpoint link in data');
	hasnt_uri('http://example.org/new2', $model, 'Test data not there yet');
	my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
	my $data_iri = iri($base_uri . 'bar/baz/bing/data');
	pattern_target($model);
	pattern_ok(
				  statement($data_iri,
								$hmns->canBe,
								$hmns->replaced),
				  statement($data_iri,
								$hmns->canBe,
								$hmns->deleted),
				  statement($data_iri,
								$hmns->canBe,
								$hmns->mergedInto),
				  'All three write triples'
				 );
	pattern_fail(
					 statement(iri($base_uri .'/bar/baz/bing'),
								  $hmns->canBe,
								  variable('o')),
					 'No canBes for the resource URI');


	note 'Post to  /bar/baz/bing/data';
	$mech->post("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle', 
													Content => "<$base_uri/foo> <http://example.org/error> \"No merged triple\"\@en" });
	is($mech->status, 400, "Posting /foo to /bar/baz/bing returns 400");

	$mech->post_ok("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle', 
														Content => "<$base_uri/bar/baz/bing> <http://example.org/new2> \"Merged triple\"\@en" });
	is($mech->status, 204, "Returns 204");

	$mech->get_ok("/bar/baz/bing");
	is($mech->ct, 'application/rdf+xml', "Correct content-type");
	like($mech->uri, qr|/bar/baz/bing/data$|, "Location is OK");
	is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	{
		my $model = return_model($mech->content, $rxparser);
		has_subject($base_uri . 'bar/baz/bing', $model, "Subject URI in content");
		has_literal('Testing with longer URI.', 'en', undef, $model, "Test phrase in content");
		hasnt_uri('http://example.org/error', $model, 'The URI in the error subject isnt in');
		hasnt_uri('http://rdfs.org/ns/void#sparqlEndpoint', $model, 'No SPARQL endpoint link in data');
		has_predicate('http://example.org/new2', $model, 'Test data now there');
	}

	note 'Write operations to /foo (not data)';
	$mech->post("/foo", { 'Content-Type' => 'text/turtle', 
								 Content => "<$base_uri/foo> <http://example.org/error> \"No merged triple\"\@en" });
	is($mech->status, 405, "Posting /foo returns 405");
	$mech->content_contains( "Write operations should be on /data-suffixed URIs, not the resource itself", "Error message for resource posts" );
	$mech->put("/foo", { 'Content-Type' => 'text/turtle',
								Content => "<$base_uri/foo> <http://example.org/error> \"No merged triple\"\@en" });
	is($mech->status, 405, "Putting /foo returns 405");
	$mech->content_contains( "Write operations should be on /data-suffixed URIs, not the resource itself", "Error message for resource puts" );
	# Seems we cannot get hold of LWP UA's delete method
	# $mech->delete("/foo");
	#	is($mech->status, 400, "Deleting /foo returns 400");
	#	$mech->content_contains( "Write operations should be on /data-suffixed URIs, not the resource itself", "Error message for resource deletes" );
	 
	note "Now post to foo/data";
	$mech->post_ok("/foo/data", { 'Content-Type' => 'text/turtle', 
											Content => "<$base_uri/foo> <http://example.org/new3> \"This worked\"\@en" });
	$mech->get_ok("/foo");
	is($mech->ct, 'application/rdf+xml', "Correct content-type");
	like($mech->uri, qr|/foo/data$|, "Location is OK");
	is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	{
		my $model = return_model($mech->content, $rxparser);
		has_subject($base_uri . '/foo', $model, "Subject URI in content");
		hasnt_uri('http://example.org/error', $model, 'The URI in the error subject isnt in');
		has_predicate('http://example.org/new3', $model, 'Test data now there');
	}

	note "Put to /foo/data";
	$mech->put("/foo/data", { 'Content-Type' => 'text/turtle', 
									  Content => "<$base_uri/foo> <http://example.org/error> \"Not permitted\"\@en" });
	is($mech->status, 403, "Putting /foo/data returns 403");

	note "PUT to bar/baz/bing/data";
	$mech->put_ok("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle', 
													  Content => "<$base_uri/bar/baz/bing> <http://example.org/new4> \"Now replacing\"\@en ; <http://example.org/new5> <http://example.org/object> ." });
	$mech->get_ok("/bar/baz/bing");
	is($mech->ct, 'application/rdf+xml', "Correct content-type");
	like($mech->uri, qr|/bar/baz/bing/data$|, "Location is OK");
	is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	{
		my $model = return_model($mech->content, $rxparser);
		has_subject($base_uri . '/bar/baz/bing', $model, "Subject URI in content");
		hasnt_uri('http://example.org/error', $model, 'The URI in the error subject isnt in');
		hasnt_uri('http://www.w3.org/2000/01/rdf-schema#label', $model, 'The label predicate is gone');
		has_predicate('http://example.org/new4', $model, 'Test data now there');
		is($model->size, 5, 'Two new triples and three hypermedia triples');
		pattern_target($model);
		pattern_ok(
					  statement($data_iri,
									$hmns->canBe,
									$hmns->replaced),
					  statement($data_iri,
									$hmns->canBe,
									$hmns->deleted),
					  statement($data_iri,
									$hmns->canBe,
									$hmns->mergedInto),
					  'All three write triples are still there'
					 );
		pattern_fail(
						 statement(iri($base_uri .'/bar/baz/bing'),
									  $hmns->canBe,
									  variable('o')),
						 'No canBes for the resource URI');
	}


}



sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}


done_testing();
