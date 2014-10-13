#!/usr/bin/perl

use FindBin qw($Bin);
use Plack::Request;

use strict;
use Test::More;# tests => 37;
use Test::RDF;
use RDF::Trine qw[iri literal blank variable statement];
use Log::Log4perl qw(:easy);
use RDF::Trine::Namespace qw(rdf rdfs foaf);
use Module::Load::Conditional qw[can_load];
use URI::Escape;

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/fragments.ttl';

BEGIN {
    use_ok('RDF::LinkedData');
}


my $void = RDF::Trine::Namespace->new('http://rdfs.org/ns/void#');
my $xsd  = RDF::Trine::Namespace->new('http://www.w3.org/2001/XMLSchema#');
my $hydra = RDF::Trine::Namespace->new('http://www.w3.org/ns/hydra/core#');

my $parser     = RDF::Trine::Parser->new( 'turtle' );
my $rxparser   = RDF::Trine::Parser->new( 'rdfxml' );
my $model = RDF::Trine::Model->temporary_model;
my $base_uri = 'http://localhost';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");

my $ec = {fragments_path => '/fragments'} ;

my $void_subject = iri($base_uri . '/#dataset-0');


{
	note 'Testing the query interface itself';

my $ld = RDF::LinkedData->new(model => $model,
										base_uri => $base_uri, 
										namespaces_as_vocabularies => 1, 
										void_config => { urispace => 'http://localhost' }, 
										fragments_config => $ec
									  );

	isa_ok($ld, 'RDF::LinkedData');

	$ld->request(Plack::Request->new({}));

	my $response = $ld->response($base_uri . '/fragments?subject=' . uri_escape_utf8('http://localhost/foo'));
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	has_literal('This is a test', 'en', undef, $retmodel, "Test phrase in content");
	pattern_target($retmodel);
	pattern_ok(
				  statement(iri($base_uri . '/foo'),
								$rdfs->label,
								literal("This is a test", 'en')),
				  statement(iri($base_uri . '/foo'),
								$foaf->page,
								iri('http://en.wikipedia.org/wiki/Foo'))
				  , 'Both triples present',
				 );

	pattern_ok(
				  statement(iri($base_uri . '/fragments?subject=' . uri_escape_utf8('http://localhost/foo')),
								$void->triples,
								literal("2", undef, $xsd->integer)),
				  statement(iri($base_uri . '/fragments?subject=' . uri_escape_utf8('http://localhost/foo')),
								$hydra->totalItems,
								literal("2", undef, $xsd->integer)),
				  , 'Triple count is correct',
				 );


	has_subject($void_subject->uri_value, $retmodel, "Void Subject URI in content");

	pattern_ok(
				  statement($void_subject,
								$rdf->type,
								$hydra->Collection),
				  statement($void_subject,
								$hydra->search,
								blank('template')),
				  statement(blank('template'),
								$hydra->template,
								literal($base_uri . '/fragments{?subject,predicate,object}')),
				  statement(blank('template'),
								$hydra->property,
								$rdf->subject),
				  statement(blank('template'),
								$hydra->variable,
								literal('subject')),
				  statement(blank('template'),
								$hydra->property,
								$rdf->predicate),
				  statement(blank('template'),
								$hydra->variable,
								literal('predicate')),
				  statement(blank('template'),
								$hydra->property,
								$rdf->object),
				  statement(blank('template'),
								$hydra->variable,
								literal('object')),
				  "Control statements OK");



	my $response = $ld->response($base_uri . '/fragments?predicate=' . uri_escape_utf8('http://www.w3.org/2000/01/rdf-schema#label') . '&object=' . uri_escape_utf8('"Testing with longer URI."@en'));
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	has_literal('Testing with longer URI.', 'en', undef, $retmodel, "Longer test phrase is in content");
	has_literal("1", undef, $xsd->integer, $retmodel, 'Triple count is correct');
	hasnt_literal('This is a test', 'en', undef, $retmodel, "Test phrase isn't in content");

	my $response = $ld->response($base_uri . '/fragments?predicate=' . uri_escape_utf8('http://www.w3.org/2000/01/rdf-schema#label') . '&object=' . uri_escape_utf8('"Nothing here."'));
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	hasnt_literal('Testing with longer URI.', 'en', undef, $retmodel, "Longer test phrase is in content");
	has_literal("0", undef, $xsd->integer, $retmodel, 'Triple count is correct');

	my $response = $ld->response($base_uri . '/fragments?predicate=' . uri_escape_utf8('http://www.w3.org/2000/01/rdf-schema#label') . '&subject=');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $parser);
	has_subject($base_uri . '/foo', $retmodel, 'Subject 1 is correct');
	has_subject($base_uri . '/bar/baz/bing', $retmodel, 'Subject 2 is correct');
	has_literal("2", undef, $xsd->integer, $retmodel, 'Triple count is correct');
	has_literal('This is a test', 'en', undef, $retmodel, "Test phrase is in content");


	my $response = $ld->response($base_uri . '/fragments?subject=&predicate=&object=');	
	isa_ok($response, 'Plack::Response');
	is($response->status, 400, "Returns 400 with all parameters empty");

	my $response = $ld->response($base_uri . '/fragments');	
	isa_ok($response, 'Plack::Response');
	is($response->status, 400, "Returns 400 with all parameters missing");

	my $response = $ld->response($base_uri . '/fragments?predicate=&object=');	
	isa_ok($response, 'Plack::Response');
	is($response->status, 400, "Returns 400 with subject missing other parameters empty");
}


{

	SKIP: {
		  skip 'You need RDF::Generator::Void for this test', 6 unless can_load( module => 'RDF::Generator::Void', version => 0.02);

		  note 'Testing the Void for fragments';
		  
		  my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri, 
												  fragments_config => $ec, 
												  void_config => { urispace => 'http://localhost' });
		  isa_ok($ld, 'RDF::LinkedData');

		  $ld->request(Plack::Request->new({}));
		  my $response = $ld->response($base_uri . '/');
		  isa_ok($response, 'Plack::Response');
		  is($response->status, 200, "Returns 200");
		  my $retmodel = return_model($response->content, $parser);
		  has_subject($void_subject->uri_value, $retmodel, "Subject URI in content");
		  has_predicate($hydra->search->uri_value, $retmodel, 'Hydra search predicate');
		  pattern_target($retmodel);
		  pattern_ok(
						 statement(
									  $void_subject,
									  $void->triples,
									  literal(4, undef, $xsd->integer)
									 ),
						 statement(
									  $void_subject,
									  $rdf->type,
									  $void->Dataset
									 ),
						 'VoID-specific statements');
		  pattern_ok(
						 statement($void_subject,
									  $rdf->type,
									  $hydra->Collection),
						 statement($void_subject,
									  $hydra->search,
									  blank('template')),
						 statement(blank('template'),
									  $hydra->template,
									  literal($base_uri . '/fragments{?subject,predicate,object}')),
						 statement(blank('template'),
									  $hydra->property,
									  $rdf->subject),
						 statement(blank('template'),
									  $hydra->variable,
									  literal('subject')),
						 statement(blank('template'),
									  $hydra->property,
									  $rdf->predicate),
						 statement(blank('template'),
									  $hydra->variable,
									  literal('predicate')),
						 statement(blank('template'),
									  $hydra->property,
									  $rdf->object),
						 statement(blank('template'),
									  $hydra->variable,
									  literal('object')),
						 "Control statements OK");
	  }
}

sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}


done_testing;
