use inc::Module::Package 'RDF';

if ($ENV{AUTOMATED_TESTING}) {
  requires 'Config::JFDI'               => 0; # If you plan to use the Plack script
  requires 'JSON'                       => 0; # If you plan to use the Plack script
  requires 'RDF::Endpoint'              => 0.03; # If you plan to use the Plack script with a SPARQL Endpoint
  requires 'Plack::Middleware::CrossOrigin' => 0; # If you'd like to add CORS headers
  requires 'RDF::Generator::Void'       => 0.04; # If you'd like a VoID description
}
