#!/usr/bin/perl

use 5.006;
use strict;
use warnings;
use Test::More;

unless ( $ENV{RELEASE_TESTING} ) {
	plan( skip_all => "Author tests not required for installation" );
}

eval "use Test::RDF::DOAP::Version";
SKIP: {
	skip "Test::RDF::DOAP::Version required", 1 if ($@);
	doap_version_ok('RDF-LinkedData', 'RDF::LinkedData');
}

eval 'use Test::CPAN::Changes';
SKIP: {
	skip "Test::CPAN::Changes required for this test", 4 if ($@);
	changes_file_ok();
}

done_testing();
