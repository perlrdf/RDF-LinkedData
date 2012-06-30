use inc::Module::Install;

name     'RDF-LinkedData';
all_from 'lib/RDF/LinkedData.pm';
author   'Kjetil Kjernsmo <kjetilk@cpan.org>';
license  'perl';

test_requires 'FindBin';
test_requires 'Test::WWW::Mechanize::PSGI';
test_requires 'Test::More' => 0.88;
test_requires 'Test::RDF' => 0.26;
test_requires 'Test::Exception';
test_requires 'Config::JFDI';
test_requires 'Test::JSON';

requires 'Moose'			=> 0;
requires 'MooseX::UndefTolerant'			=> 0;
requires 'MooseX::Log::Log4perl::Easy'  => 0;
requires 'Log::Log4perl'		=> 0;
requires 'RDF::Trine'			=> 0.133;
requires 'Scalar::Util'			=> 0;
requires 'Plack'                        => 0.9939;
requires 'namespace::autoclean'         => 0.12;
requires 'HTTP::Headers'                => 0;
requires 'RDF::Helper::Properties'      => 0.10;
requires 'URI'                          => 1.52;
requires 'Module::Load::Conditional'    => 0;
requires 'Encode'                       => 0;
requires 'RDF::RDFa::Generator'         => 0.102;
requires 'HTML::HTML5::Writer'          => 0;

recommends 'Config::JFDI'               => 0; # If you plan to use the Plack script
recommends 'JSON'                       => 0; # If you plan to use the Plack script
recommends 'RDF::Endpoint'              => 0.03; # If you plan to use the Plack script with a SPARQL Endpoint
recommends 'Plack::Middleware::CrossOrigin' => 0; # If you'd like to add CORS headers
recommends 'RDF::Generator::Void'       => 0.04; # If you'd like a VoID description

install_script 'script/linked_data.psgi';

author_tests('xt');

auto_set_repository;

resources
  bugtracker    => "https://github.com/kjetilk/RDF-LinkedData/issues";

rdf_metadata;
write_doap_changes;

sign;

WriteAll;

