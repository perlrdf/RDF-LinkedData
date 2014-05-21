package RDF::LinkedData::Fragments;

use Moose;
use namespace::autoclean;

use RDF::Trine qw[iri literal blank statement];


with 'MooseX::Log::Log4perl::Easy';

BEGIN {
	if ($ENV{TEST_VERBOSE}) {
		Log::Log4perl->easy_init( { level   => $TRACE,
											 category => 'RDF.LinkedData' 
										  } );
	} else {
		Log::Log4perl->easy_init( { level   => $FATAL,
											 category => 'RDF.LinkedData' 
										  } );
	}
}




=head1 NAME

RDF::LinkedData::Fragments - A simple Linked Data Fragments server implementation

1;
