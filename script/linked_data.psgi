#!/usr/bin/perl

use RDF::LinkedData;
use Plack::Request;
use RDF::Trine;
use Config::JFDI;
use Carp qw(confess);

=head1 NAME

linked_data.psgi - A simple Plack server for RDF as linked data


=head1 SYNOPSIS

  plackup ./script/linked_data.psgi --host localhost --port 3000

=head1 DESCRIPTION

To use a server based on L<RDF::LinkedData>, create a database with
triples, using L<RDF::Trine>. There is an example in
C<write_sqlite-db.pl> in the distribution that converts a Turtle file
to a suitable SQLite database, other databases can be handled in a
similar manner.

Next, you need to construct a L<RDF::Trine::Store> config string, see
the documentation in that module for further information, and also the
above mentioned script.

Then, you need a config file. There's a companion
C<rdf_linkeddata.json> that contains a JSON file that configures this
script to use a minimal example database with just three triples. In
this file, there is a L<store> parameter, which must contain the
L<RDF::Trine::Store> config string and a C<base> URI. This defaults to
L<http://localhost:3000>, which is what this script also defaults to.

The configuration is done using L<Config::JFDI> and all its features
can be used. Importantly, you can set the C<RDF_LINKEDDATA_CONFIG>
environment variable to point to the config file you want to use. See
also L<Catalyst::Plugin::ConfigLoader> for more information on how to
use this config system.

The following documentation is adapted from the L<RDF::LinkedData::Apache>,
which preceeded this script.

=over 4 

=item * C<http://host.name/rdf/example>

Will return an HTTP 303 redirect based on the value of the request's
Accept header. If the Accept header contains a recognized RDF media
type or there is no Accept header, the redirect will be to
C<http://host.name/rdf/example/data>, otherwise to
C<http://host.name/rdf/example/page>. If the URI has a foaf:homepage
or foaf:page predicate, the redirect will in the latter case instead
use the first encountered object URI.

=item * C<http://host.name/rdf/example/data>

Will return a bounded description of the C<http://host.name/rdf/example>
resource in an RDF serialization based on the Accept header. If the Accept
header does not contain a recognized media type, RDF/XML will be returned.

=item * C<http://host.name/rdf/example/page>

Will return an HTML description of the C<http://host.name/rdf/example>
resource including RDFa markup, or, if the URI has a foaf:homepage or
foaf:page predicate, a 301 redirect to that object.

=back

If the RDF resource for which data is requested is not the subject of any RDF
triples in the underlying triplestore, the /page and /data redirects will not take
place, and a HTTP 404 (Not Found) will be returned.

The HTML description of resources will be enhanced by having metadata about the
predicate of RDF triples loaded into the same triplestore. Currently, the
relevant metadata includes rdfs:label and dc:description statements about
predicates. For example, if the triplestore contains the statement

<http://host.name/rdf/example> <http://example/date> "2010" .

then also including the triple

<http://example/date> <http://www.w3.org/2000/01/rdf-schema#label> "Creation Date" .

Would allow the HTML description of L<http://host.name/rdf/example> to include
a description including:

Creation Date: 2010

instead of the less specific:

date: 2010

which is simply based on attempting to extract a useful suffix from the
predicate URI.

=cut

$main::linked_data = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);

    unless ($req->method eq 'GET') {
        return [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ];
    }

    my $config = Config::JFDI->open( name => "RDF::LinkedData") or confess "Couldn't find config";

    my $ld = RDF::LinkedData->new(store => $config->{store}, base => $config->{base});
    my $uri = $req->path_info;

    if ($req->path_info =~ m!^(.+?)/?(page|data)$!) {
        $uri = $1;
        $ld->type($2);
    }
    $ld->headers_in($req->headers);
    return $ld->response($uri)->finalize;
}

__END__

=head1 FEEDBACK WANTED

Please contact the author if this documentation is unclear. It is
really very simple to get it running, so if it appears difficult, this
documentation is most likely to blame.

=head1 AUTHOR

Kjetil Kjernsmo C<< <kjetilk@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2010 ABC Startsiden AS. This program is free software;
you can redistribute it and/or modify it under the same terms as Perl
itself.

=cut
