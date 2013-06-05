#!/usr/bin/perl

use FindBin qw($Bin);
use Plack::Request;

use strict;
use Test::More;					  # tests => 37;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use RDF::Trine::Namespace;
use Log::Log4perl qw(:easy);
use Module::Load::Conditional qw[check_install];


Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/basic.ttl';

use_ok('RDF::LinkedData');


my $parser     = RDF::Trine::Parser->new( 'turtle' );
my $rxparser   = RDF::Trine::Parser->new( 'rdfxml' );
my $model = RDF::Trine::Model->temporary_model;
my $base_uri = 'http://localhost';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");

my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri);
$ld->request(Plack::Request->new({CONTENT_TYPE => 'text/turtle'}));

isa_ok($ld, 'RDF::LinkedData');
cmp_ok($ld->count, '>', 0, "There are triples in the model");
	
note "Get /foo/data, with append privs";
$ld->type('data');
$ld->clear_auth_level;
$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Append');

{
	note "Try with malformed data";
	my $mergeresponse = $ld->merge($base_uri . '/foo', "This is certainly not valid Turtle");
	isa_ok($mergeresponse, 'Plack::Response');
	is($mergeresponse->status, 400, "Returns 400");
	like($mergeresponse->content, qr/Couldn't parse the payload/, 'Error body OK');
}
{
	note "Post /foobar data to /foo";
	my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foobar> <http://example.org/new1> \"Merged triple\"\@en");
	isa_ok($mergeresponse, 'Plack::Response');
	is($mergeresponse->status, 400, "Returns 400");
	is($mergeresponse->content, 'The payload contained no relevant triples', 'Error body OK');
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);

	cmp_ok($retmodel->size, '>', 0, "There are triples in the model");
	hasnt_uri('http://example.org/new1', $retmodel, 'The predicate didnt go in');
}

note "Start adding stuff";
{
	my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foo> <http://example.org/new2> \"Merged triple\"\@en");
	isa_ok($mergeresponse, 'Plack::Response');
	is($mergeresponse->status, 204, "Returns 204");
}
my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
{
	$ld->type('data');
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);
	my $data_iri = iri($base_uri . '/foo');
	has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
	has_literal('Merged triple', 'en', undef, $retmodel, "New test phrase in content");
	hasnt_uri($hmns->deleted->uri_value, $retmodel, 'No deleted URIs');
	hasnt_uri($hmns->replaced->uri_value, $retmodel, 'No replaced URIs');
	pattern_target($retmodel);
	pattern_ok(
				  statement($data_iri,
								$hmns->canBe,
								$hmns->mergedInto),
				  'MergedInto OK');
	pattern_fail(
					 statement(iri($base_uri . '/foo'),
								  $hmns->canBe,
								  variable('o')),
					 'No canBes for the resource URI');

}



{
	note "Shouldnt be able to merge hypermedia triples";
	$ld->type('data');
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);
	has_uri($hmns->mergedInto->uri_value, $retmodel, 'Has mergedInto URI');
	$ld->clear_auth_level;
	hasnt_uri($hmns->deleted->uri_value, $retmodel, 'No deleted URIs');
	hasnt_uri($hmns->replaced->uri_value, $retmodel, 'No replaced URIs');
	hasnt_uri($hmns->mergedInto->uri_value, $retmodel, 'No mergedInto URIs');
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Append');
	{
		my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foo> " . $hmns->canBe . " " . $hmns->deleted . " ; <http://example.org/new2> \"Is actually merged\"\@en");
		isa_ok($mergeresponse, 'Plack::Response');
		is($mergeresponse->status, 204, "Returns 204");
		$ld->type('data');
		my $mresponse = $ld->response($base_uri . '/foo');
		isa_ok($mresponse, 'Plack::Response');
		is($mresponse->status, 200, "Returns 200");
		my $mretmodel = return_model($response->content, $rxparser);
		hasnt_uri($hmns->deleted->uri_value, $mretmodel, 'Still no deleted URIs');
		hasnt_uri($hmns->replaced->uri_value, $mretmodel, 'No replaced URIs');
		has_uri($hmns->mergedInto->uri_value, $mretmodel, 'Has mergedInto URIs');
		has_literal('Is actually merged', 'en', undef, $mretmodel, "But test phrase is in content");

	}
	{
		$ld->clear_auth_level;
		my $mresponse = $ld->response($base_uri . '/foo');
		my $mretmodel = return_model($mresponse->content, $rxparser);
		hasnt_uri($hmns->mergedInto->uri_value, $retmodel, 'No mergedInto URIs after cleared authlevel');
	}
}

{
	note "Merge stuff when not authorized";
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read');
	my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foo> <http://example.org/new3> \"l33t h4X0R\"\@en");
	isa_ok($mergeresponse, 'Plack::Response');
	is($mergeresponse->status, 401, "Returns 401");
	$ld->type('data');
	my $cresponse = $ld->response($base_uri . '/foo');
	my $cretmodel = return_model($cresponse->content, $rxparser);
	hasnt_uri($hmns->mergedInto->uri_value, $cretmodel, 'No mergedInto URIs though we tried');
	hasnt_uri('http://example.org/new3', $cretmodel, 'The predicate didnt go in');
}

{
	note "Merge with Write set";
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Write');
	my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foo> <http://example.org/new4> \"Goes in\"\@en");
	isa_ok($mergeresponse, 'Plack::Response');
	is($mergeresponse->status, 204, "Returns 204");
	my $data_iri = iri($base_uri . '/foo');
	{
		$ld->type('data');
		my $cresponse = $ld->response($base_uri . '/foo');
		my $cretmodel = return_model($cresponse->content, $rxparser);
		pattern_target($cretmodel);
		pattern_ok(
					  statement($data_iri,
									iri('http://example.org/new4'),
									literal('Goes in', 'en')),
					  statement($data_iri,
									iri('http://www.w3.org/2000/01/rdf-schema#label'),
									literal('This is a test', 'en')),
					  'MergedInto OK after append with write');
		pattern_fail(
						 statement(iri($base_uri . '/foo'),
									  $hmns->canBe,
									  variable('o')),
						 'No canBes for the resource URI');

	}

	{
		note "Put will replace";
		my $putresponse = $ld->replace($base_uri . '/foo', "<$base_uri/foo> <http://example.org/new5> \"Goes in\"\@en ; <http://www.w3.org/2000/01/rdf-schema\#label> \"Updated triple\"\@en .");
		isa_ok($putresponse, 'Plack::Response');
		is($putresponse->status, 204, "Returns 204");
		$ld->type('data');
		my $cresponse = $ld->response($base_uri . '/foo');
		my $cretmodel = return_model($cresponse->content, $rxparser);
		pattern_target($cretmodel);
		pattern_ok(
					  statement($data_iri,
									iri('http://example.org/new5'),
									literal('Goes in', 'en')),
					  statement($data_iri,
									iri('http://www.w3.org/2000/01/rdf-schema#label'),
									literal('"Updated triple', 'en')),
					  'MergedInto OK after put with write');
		hasnt_uri('http://example.org/new4', $cretmodel, 'The new4 predicate has disappeared.');
		pattern_fail(
						 statement(iri($base_uri . '/foo'),
									  $hmns->canBe,
									  variable('o')),
						 'No canBes for the resource URI');

		note "Delete";
		is($ld->replace($base_uri . '/foo/bar/baz')->status, 401, "Returns 401 for delete to other resource");
		is($ld->replace($base_uri . '/foobaz')->status, 404, "Returns 404 for access to unknown");
		my $deleteresponse = $ld->replace($base_uri . '/foo');
		isa_ok($deleteresponse, 'Plack::Response');
		is($deleteresponse->status, 204, "Returns 204");
		$ld->type('data');
		my $dresponse = $ld->response($base_uri . '/foo');
		isa_ok($dresponse, 'Plack::Response');
		is($dresponse->status, 404, "Returns 404 after deletion");


	}

}




done_testing;


sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	return $retmodel unless ($content) ;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}
