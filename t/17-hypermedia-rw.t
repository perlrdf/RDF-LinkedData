#!/usr/bin/perl

use FindBin qw($Bin);
use Plack::Request;

use strict;
use Test::More;# tests => 37;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use RDF::Trine::Namespace;
use Log::Log4perl qw(:easy);
use Module::Load::Conditional qw[check_install];


Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/basic.ttl';

use_ok('RDF::LinkedData');


my $parser     = RDF::Trine::Parser->new( 'turtle' );
my $model = RDF::Trine::Model->temporary_model;
my $base_uri = 'http://localhost';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");

{
	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri);
	
	isa_ok($ld, 'RDF::LinkedData');
	cmp_ok($ld->count, '>', 0, "There are triples in the model");
	
	note 'Basic checking auth_levels';

	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read');
	is($ld->has_auth_level('read'), 1, 'Has read auth level ok');
	is($ld->has_auth_level('write'), 0, 'Hasnt write auth level ok');
	is($ld->has_auth_level('append'), 0, 'Hasnt append auth level ok');
	$ld->clear_auth_level;
	is($ld->has_auth_level('read'), 0, 'Hasnt read auth level after clear');
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Write');
	is($ld->has_auth_level('read'), 1, 'Has read auth level ok');
	is($ld->has_auth_level('write'), 1, 'Has write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');
	$ld->clear_auth_level;
	is($ld->has_auth_level('read'), 0, 'Hasnt read auth level ok');
	is($ld->has_auth_level('write'), 0, 'Hasnt write auth level ok');
	is($ld->has_auth_level('append'), 0, 'Hasnt append auth level ok');
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Append');
	is($ld->has_auth_level('read'), 1, 'Has read auth level ok');
	is($ld->has_auth_level('write'), 0, 'Hasnt write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');
	$ld->clear_auth_level;
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Write','http://www.w3.org/ns/auth/acl#Append');
	is($ld->has_auth_level('read'), 0, 'Hasnt read auth level ok');
	is($ld->has_auth_level('write'), 1, 'Has write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');
	$ld->clear_auth_level;
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Write','http://www.w3.org/ns/auth/acl#Append');
	is($ld->has_auth_level('read'), 1, 'Has read auth level ok');
	is($ld->has_auth_level('write'), 1, 'Has write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');


	{
		note "Get /foo, ensure nothing changed.";
		$ld->request(Plack::Request->new({}));
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 303, "Returns 303");
		like($response->header('Location'), qr|/foo/data$|, "Location is OK");
	}
	
	{
		note "Get /foo/data, with all privs";
		$ld->type('data');
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
		my $data_iri = iri($base_uri . '/foo/data');

		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
		pattern_target($retmodel);
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
					 )
	}

	{
		note "Get /foo/data, with no privs";
		$ld->type('data');
		$ld->clear_auth_level;
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
		my $data_iri = iri($base_uri . '/foo/data');

		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
		hasnt_uri($hmns->canBe->uri_value, $retmodel, 'No rw URIs');
	}

	{
		note "Get /foo/data, with ro privs";
		$ld->type('data');
		$ld->clear_auth_level;
		$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read');
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
		my $data_iri = iri($base_uri . '/foo/data');

		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
		hasnt_uri($hmns->canBe->uri_value, $retmodel, 'No rw URIs');
	}
	{
		note "Get /foo/data, with append privs";
		$ld->type('data');
		$ld->clear_auth_level;
		$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Append');
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
		my $data_iri = iri($base_uri . '/foo/data');

		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
		hasnt_uri($hmns->deleted->uri_value, $retmodel, 'No deleted URIs');
		hasnt_uri($hmns->replaced->uri_value, $retmodel, 'No replaced URIs');
		pattern_target($retmodel);
		pattern_ok(
					  statement($data_iri,
									$hmns->canBe,
									$hmns->mergedInto),
					  'MergedInto OK');

	}
}


note 'Now really do RW';
TODO: {
  local $TODO = 'Failing tests for TDD for RW support';
{
	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri);

	isa_ok($ld, 'RDF::LinkedData');
	cmp_ok($ld->count, '>', 0, "There are triples in the model");
	
	note "Get /foo/data, with append privs";
	$ld->type('data');
	$ld->clear_auth_level;
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Append');
	{
		my $turtle = "This is certainly not valid Turtle";
		open my ($str_fh), '<', \$turtle;
		$ld->request(Plack::Request->new({
													 REQUEST_URI => $base_uri . '/foo/data',
													 CONTENT_TYPE => 'text/turtle',
													 'psgi.input' => $str_fh
													}));
		my $mergeresponse = $ld->merge($base_uri . '/foo');
		isa_ok($mergeresponse, 'Plack::Response');
		is($mergeresponse->status, 400, "Returns 400");
		like($mergeresponse->content, qr/Couldn't parse the payload/, 'Error body OK');
	}
	{
		my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foobar> <http://example.org/new1> \"Merged triple\"\@en");
		isa_ok($mergeresponse, 'Plack::Response');
		is($mergeresponse->status, 400, "Returns 400");
		is($mergeresponse->content, 'The payload contained no relevant triples', 'Error body OK');
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		cmp_ok($retmodel->size, '>', 0, "There are triples in the model");
		hasnt_uri('http://example.org/new1', $retmodel, 'The predicate didnt go in');
	}
	{
		my $mergeresponse = $ld->merge($base_uri . '/foo', "<$base_uri/foo> <http://example.org/new2> \"Merged triple\"\@en");
		isa_ok($mergeresponse, 'Plack::Response');
		is($mergeresponse->status, 204, "Returns 204");
	}
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	my $hmns = RDF::Trine::Namespace->new('http://example.org/hypermedia#');
	my $data_iri = iri($base_uri . '/foo/data');
	
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
}

done_testing;


sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}
