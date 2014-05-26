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

Log::Log4perl->easy_init( { level   => $FATAL } ) unless $ENV{TEST_VERBOSE};

my $file = $Bin . '/data/basic.ttl';

BEGIN {
    use_ok('RDF::LinkedData');
    use_ok('RDF::Helper::Properties');
    use_ok('RDF::Trine::Parser');
    use_ok('RDF::Trine::Model');
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

my $ec;
$ec = {fragments_path => '/fragments'} ;

my $void_subject = iri($base_uri . '/#dataset-0');


TODO: {
	local $TODO = "Implementing Linked Data Fragments";

	note 'Testing the query interface itself';

	my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri, fragments_config => $ec);
	my $response = $ld->response($base_uri . '/fragments?subject=http://localhost/foo');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);
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
				  statement(iri($base_uri . '/fragments?subject=http://localhost/foo'),
								$void->triples,
								literal("2", undef, $xsd->integer)),
				  statement(iri($base_uri . '/fragments?subject=http://localhost/foo'),
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



	my $response = $ld->response($base_uri . '/fragments?predicate=http://www.w3.org/2000/01/rdf-schema#label&object="Testing with longer URI."@en');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);
	has_literal('Testing with longer URI.', 'en', undef, $retmodel, "Longer test phrase is in content");
	has_literal("1", undef, $xsd->integer);
	hasnt_literal('This is a test', 'en', undef, $retmodel, "Test phrase isn't in content");

	my $response = $ld->response($base_uri . '/fragments?predicate=http://www.w3.org/2000/01/rdf-schema#label&subject=');
	isa_ok($response, 'Plack::Response');
	is($response->status, 200, "Returns 200");
	my $retmodel = return_model($response->content, $rxparser);
	has_subject($base_uri . '/foo', $retmodel, 'Subject 1 is correct');
	has_subject($base_uri . '/bar/baz/bing', $retmodel, 'Subject 2 is correct');
	has_literal("2", undef, $xsd->integer);
	hasnt_literal('This is a test', 'en', undef, $retmodel, "Test phrase isn't in content");


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


TODO: {
	local $TODO = "Implementing Linked Data Fragments";

	SKIP: {
		  skip 'You need RDF::Generator::Void for this test', 6 unless can_load( module => 'RDF::Generator::Void', version => 0.02);

		  note 'Testing the Void for fragments';
		  
		  my $ld = RDF::LinkedData->new(model => $model, base_uri=>$base_uri, 
												  fragments_config => $ec, 
												  void_config => { urispace => 'http://localhost' });
		  my $response = $ld->response($base_uri . '/');
		  isa_ok($response, 'Plack::Response');
		  is($response->status, 200, "Returns 200");
		  my $retmodel = return_model($response->content, $rxparser);
		  has_subject($void_subject, $retmodel, "Subject URI in content");
		  has_predicate($hydra->search->uri_value, $retmodel, 'Hydra search predicate');
		  pattern_target($retmodel);
		  pattern_ok(
						 statement(
									  $void_subject,
									  $void->triples,
									  literal(3, undef, $xsd->integer)
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

done_testing;
