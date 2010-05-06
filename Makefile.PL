use inc::Module::Install;

name     'RDF-LinkedData';
all_from 'lib/RDF/LinkedData.pm';
author   'Kjetil Kjernsmo <kjetilk@cpan.org>';
license  'perl';

test_requires 'FindBin';
test_requires 'HTTP::Headers';
test_requires 'Test::WWW::Mechanize::Mojo';
test_requires 'Test::More';
test_requires 'Test::Exception';

requires 'Error'			=> 0;
requires 'Log::Log4perl'		=> 0;
requires 'RDF::Trine'			=> 0.122;
requires 'Scalar::Util'			=> 0;

recommends 'Mojolicious::Lite'          => 0; # The built-in server uses this
recommends 'HTTP::Headers'              => 0; # To run the built-in server

auto_set_repository;
auto_set_bugtracker;

write_doap_changes;

sign;

WriteAll;

