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



{
    note "Get /bar/baz/bing, ask for RDF/XML";
    my $mech = Test::WWW::Mechanize::PSGI->new(app => $tester);
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
	 my $data_iri = iri($base_uri . '/bar/baz/bing/data');
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
	 note 'Post to  /bar/baz/bing/data';
	 $mech->post_ok("/bar/baz/bing/data", { 'Content-Type' => 'text/turtle', 
														 Content => "<$base_uri/foo> <http://example.org/new2> \"Merged triple\"\@en" });
	 is($mech->status, 204, "Returns 204");
    $mech->get_ok("/bar/baz/bing");
    is($mech->ct, 'application/rdf+xml', "Correct content-type");
    like($mech->uri, qr|/bar/baz/bing/data$|, "Location is OK");
    is_valid_rdf($mech->content, 'rdfxml', 'Returns valid RDF/XML');
	 my $model = return_model($mech->content, $rxparser);
    has_subject($base_uri . 'bar/baz/bing', $model, "Subject URI in content");
    has_literal('Testing with longer URI.', 'en', undef, $model, "Test phrase in content");
	 hasnt_uri('http://rdfs.org/ns/void#sparqlEndpoint', $model, 'No SPARQL endpoint link in data');
	 has_predicate('http://example.org/new2', $model, 'Test data now there');

}



sub return_model {
	my ($content, $parser) = @_;
	my $retmodel = RDF::Trine::Model->temporary_model;
	$parser->parse_into_model( $base_uri, $content, $retmodel );
	return $retmodel;
}


done_testing();
