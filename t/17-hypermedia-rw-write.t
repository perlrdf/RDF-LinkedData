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



TODO: {
	local $TODO = 'Failing tests for TDD for RW support';
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
	}



	{
		note "Shouldnt be able to merge hypermedia triples";
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
			my $mergeresponse = $ld->merge("<$base_uri/foo> " . $hmns->canBe . " " . $hmns->deleted . " ; <http://example.org/new2> \"Is actually merged\"\@en");
			isa_ok($mergeresponse, 'Plack::Response');
			is($mergeresponse->status, 204, "Returns 204");
			my $mretmodel = return_model($mergeresponse->content, $rxparser);
			hasnt_uri($hmns->deleted->uri_value, $mretmodel, 'Still no deleted URIs');
			hasnt_uri($hmns->replaced->uri_value, $mretmodel, 'No replaced URIs');
			has_uri($hmns->mergedInto->uri_value, $mretmodel, 'Has mergedInto URIs');
			has_literal('Is actually merged', 'en', undef, $mretmodel, "But test phrase is in content");

		}
		$ld->clear_auth_level;
		hasnt_uri($hmns->mergedInto->uri_value, $retmodel, 'No mergedInto URIs');
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
