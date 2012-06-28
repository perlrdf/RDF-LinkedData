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
use RDF::Trine::Namespace qw(rdf);

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
my $model = RDF::Trine::Model->temporary_model;
my $base_uri = 'http://localhost';
$parser->parse_file_into_model( $base_uri, $file, $model );

ok($model, "We have a model");

my $ld = RDF::LinkedData->new(model => $model, base_uri => $base_uri, void_config => { something => 1 });

isa_ok($ld, 'RDF::LinkedData');
cmp_ok($ld->count, '>', 0, "There are triples in the model");


{
	note "Get /";
	$ld->request(Plack::Request->new({}));
	my $response = $ld->response($base_uri);
	isa_ok($response, 'Plack::Response');
	my $content = $response->content;
	is_valid_rdf($content, 'turtle', 'Returns valid Turtle');
	$parser->parse_into_model( $base_uri, $content, $model );
	has_subject($base_uri . '/#dataset-0', $model, "Subject URI in content");
	pattern_target($model);
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


done_testing;
