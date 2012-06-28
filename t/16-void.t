#!/usr/bin/perl

use FindBin qw($Bin);
use Plack::Request;

use strict;
use Test::More;#tests => 38;
use Test::RDF;
use Log::Log4perl qw(:easy);
use Module::Load::Conditional qw[check_install];
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use RDF::Trine::Namespace qw(rdf rdfs);
use RDF::Trine::Store::Hexastore;

unless (defined(check_install( module => 'RDF::Generator::Void', version => 0.02))) {
  plan skip_all => 'You need RDF::Generator::Void for this test'
}

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/basic.ttl';

BEGIN {
    use_ok('RDF::LinkedData');
    use_ok('RDF::Helper::Properties');
    use_ok('RDF::Trine::Parser');
    use_ok('RDF::Trine::Model');
}



my $parser     = RDF::Trine::Parser->new( 'turtle' );
my $store = RDF::Trine::Store::Hexastore->temporary_store;
my $model = RDF::Trine::Model->new($store);
my $base_uri = 'http://localhost';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");
is($model->size, 3, "We have a model with 3 statements");

my $ld = RDF::LinkedData->new(model => $model, base_uri => $base_uri, void_config => { something => 1 });

isa_ok($ld, 'RDF::LinkedData');
is($ld->count, 3, "There are 3 triples in the model");

{
	note "Basic VoID test";
	$ld->request(Plack::Request->new({}));
	my $response = $ld->response($base_uri);
	isa_ok($response, 'Plack::Response');
	my $content = $response->content;
	is_valid_rdf($content, 'turtle', 'Returns valid Turtle');
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	has_subject($base_uri . '/#dataset-0', $retmodel, "Subject URI in content");
	pattern_target($retmodel);
	my $void = RDF::Trine::Namespace->new('http://rdfs.org/ns/void#');
	my $xsd  = RDF::Trine::Namespace->new('http://www.w3.org/2001/XMLSchema#');
	pattern_ok(
				  statement(
								iri($base_uri . '/#dataset-0'),
								$void->triples,
								literal(3, undef, $xsd->integer)
							  ),
				  statement(
								iri($base_uri . '/#dataset-0'),
								$rdf->type,
								$void->Dataset
							  ),
				  'Common statements are there');
}

{
	note "Add a statement";

	is($ld->count, 3, "There are 3 triples in the model");
	$ld->model->add_statement(statement(iri($base_uri . '/foo'), $rdfs->label, literal('DAHUT')));
	is($ld->count, 4, "There are 4 triples in the model");
	isnt($ld->last_etag, $ld->current_etag, 'Etags have changed');
	$ld->type('data');
	$ld->request(Plack::Request->new({}));
	my $fresponse = $ld->response($base_uri .'/foo');
	isa_ok($fresponse, 'Plack::Response');
	like($fresponse->content, qr/DAHUT/, 'Test string in content');

	$ld->request(Plack::Request->new({}));
	my $response = $ld->response($base_uri);
	isa_ok($response, 'Plack::Response');
	my $content = $response->content;
	is_valid_rdf($content, 'turtle', 'Returns valid Turtle');
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	has_subject($base_uri . '/#dataset-0', $retmodel, "Subject URI in content");
	pattern_target($retmodel);
	my $s = RDF::Trine::Serializer->new('turtle');
	diag $s->serialize_model_to_string($retmodel);
	my $void = RDF::Trine::Namespace->new('http://rdfs.org/ns/void#');
	my $xsd  = RDF::Trine::Namespace->new('http://www.w3.org/2001/XMLSchema#');
	pattern_ok(
				  statement(
								iri($base_uri . '/#dataset-0'),
								$void->triples,
								literal(4, undef, $xsd->integer)
							  ),
				  statement(
								iri($base_uri . '/#dataset-0'),
								$rdf->type,
								$void->Dataset
							  ),
				  'Common statements are there');
}



done_testing;
