#!/usr/bin/perl

use FindBin qw($Bin);
use Plack::Request;

use strict;
use Test::More;# tests => 37;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use Log::Log4perl qw(:easy);
use Module::Load::Conditional qw[check_install];

unless (defined(check_install( module => 'RDF::ACL', version => 0.1))) {
  plan skip_all => 'You need RDF::ACL for this test'
}


Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/basic.ttl';

use_ok('RDF::LinkedData');
use_ok('RDF::ACL');



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
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Read','http://www.w3.org/ns/auth/acl#Write','http://www.w3.org/ns/auth/acl#Append');
	is($ld->has_auth_level('read'), 1, 'Has read auth level ok');
	is($ld->has_auth_level('write'), 1, 'Has write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');
	$ld->clear_auth_level;
	$ld->add_auth_levels('http://www.w3.org/ns/auth/acl#Write','http://www.w3.org/ns/auth/acl#Append');
	is($ld->has_auth_level('read'), 0, 'Hasnt read auth level ok');
	is($ld->has_auth_level('write'), 1, 'Has write auth level ok');
	is($ld->has_auth_level('append'), 1, 'Has append auth level ok');

	
done_testing;


 exit;
	{
		note "Get /foo, ensure nothing changed.";
		$ld->request(Plack::Request->new({}));
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 303, "Returns 303");
		like($response->header('Location'), qr|/foo/data$|, "Location is OK");
	}
	
	{
		note "Get /foo/data";
		$ld->type('data');
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
	 SKIP: {
			skip "No endpoint configured", 2 unless ($ld->has_endpoint);
			has_uri($base_uri . '/sparql', $retmodel, 'SPARQL Endpoint URI is in model');
			pattern_target($retmodel);
		 SKIP: {
				skip "Redland behaves weirdly", 1 if ($RDF::Trine::Parser::Redland::HAVE_REDLAND_PARSER);
			pattern_ok(
						  statement(
										iri($base_uri . '/foo/data'),
										iri('http://rdfs.org/ns/void#inDataset'),
										variable('void')
									  ),
						  statement(
										variable('void'),
										iri('http://rdfs.org/ns/void#sparqlEndpoint'),
										iri($base_uri . '/sparql'),
									  ),
						  'SPARQL Endpoint is present'
						 )
		}
		}
	}
}

{
	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri);
	
	isa_ok($ld, 'RDF::LinkedData');
	cmp_ok($ld->count, '>', 0, "There are triples in the model");
	
	
	{
		note "Get /foo, ensure nothing changed.";
		$ld->request(Plack::Request->new({}));
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 303, "Returns 303");
		like($response->header('Location'), qr|/foo/data$|, "Location is OK");
	}
	
	{
		note "Get /foo/data, namespaces set";
		$ld->type('data');
		$ld->namespaces ( { skos => 'http://www.w3.org/2004/02/skos/core#', dct => 'http://purl.org/dc/terms/' } );
		my $response = $ld->response($base_uri . '/foo');
		isa_ok($response, 'Plack::Response');
		is($response->status, 200, "Returns 200");
		my $retmodel = return_model($response->content, $parser);
		has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
		has_object_uri('http://www.w3.org/2004/02/skos/core#', $retmodel, 'SKOS URI is present');
		pattern_target($retmodel);
		 SKIP: {
				skip "Redland behaves weirdly", 1 if ($RDF::Trine::Parser::Redland::HAVE_REDLAND_PARSER);
		pattern_ok(
						  statement(
										iri($base_uri . '/foo/data'),
										iri('http://rdfs.org/ns/void#inDataset'),
										variable('void')
									  ),
						  statement(
										variable('void'),
										iri('http://rdfs.org/ns/void#vocabulary'),
										iri('http://www.w3.org/2004/02/skos/core#'),
									  ),
						  statement(
										variable('void'),
										iri('http://rdfs.org/ns/void#vocabulary'),
										iri('http://purl.org/dc/terms/'),
									  ),
					    'Vocabularies are present'
						 )
		}
	}

}


{
	note "Now testing no endpoint";
	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri);
	isa_ok($ld, 'RDF::LinkedData');
	cmp_ok($ld->count, '>', 0, "There are triples in the model");
	$ld->type('data');
	$ld->request(Plack::Request->new({}));
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
	hasnt_uri('http://rdfs.org/ns/void#sparqlEndpoint', $retmodel, 'No SPARQL endpoint entered');
}
{
	note "Now testing no endpoint";
	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri, namespaces_as_vocabularies => 0);
	isa_ok($ld, 'RDF::LinkedData');
	cmp_ok($ld->count, '>', 0, "There are triples in the model");
	$ld->type('data');
	$ld->request(Plack::Request->new({}));
	my $response = $ld->response($base_uri . '/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
	hasnt_uri('http://rdfs.org/ns/void#vocabulary', $retmodel, 'No vocabs entered');
}



done_testing;


sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}
