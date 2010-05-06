#!/usr/bin/perl

use strict;
use warnings;

use RDF::Trine::Store::DBI::SQLite;

my ($outname) = $ARGV[0] =~ m/^(.+)\.ttl$/; 
my $store = RDF::Trine::Store->new_with_string("DBI;$outname;DBI:SQLite:$outname.db;user;pass");
$store->init;
use RDF::Trine::Parser;
use RDF::Trine::Model;
my $model = RDF::Trine::Model->new($store);
my $parser     = RDF::Trine::Parser->new( 'turtle' );
$parser->parse_file_into_model( 'http://localhost:3000', $ARGV[0], $model );

print "Got " . $model->count_statements . " statements.\n";

1;
