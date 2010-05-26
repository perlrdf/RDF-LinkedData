#!/usr/bin/perl

=head1 NAME

linked_data_mojoserver.pl - A simple Mojolicious::Lite server for RDF as linked data

=head1 SYNOPSIS


  linked_data_mojoserver.pl daemon


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
C<linked_data_mojoserver.json> that contains a JSON file that
configures this script to use a minimal example database with just two
triples. In this file, there is a L<store> parameter, which must
contain the L<RDF::Trine::Store> config string and a C<base> URI. This
defaults to L<http://localhost:3000>, which is what this script also
defaults to.


The following documentation is adapted from the L<RDF::LinkedData::Apache>,
which preceeded this script.

=over 4

* L<http://host.name/rdf/example>

Will return an HTTP 303 redirect based on the value of the request's Accept
header. If the Accept header contains a recognized RDF media type, the redirect
will be to L<http://host.name/rdf/example/data>, otherwise to
L<http://host.name/rdf/example/page>

* L<http://host.name/rdf/example/data>

Will return a bounded description of the L<http://host.name/rdf/example>
resource in an RDF serialization based on the Accept header. If the Accept
header does not contain a recognized media type, RDF/XML will be returned.

* L<http://host.name/rdf/example/page>

Will return an HTML description of the L<http://host.name/rdf/example> resource
including RDFa markup.

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

use Mojolicious::Lite;

use RDF::LinkedData;
use RDF::LinkedData::Predicates;
use HTTP::Headers;
use Mojo::Log;

my $log = Mojo::Log->new;

my $config = plugin 'json_config';#  => {file => '/etc/linked-data-server.json'};

get '(*uri)/:type' => [type => qr(data|page)] => sub {
    my $self = shift;
    my $ld = RDF::LinkedData->new(config => $config->{store}, base => $config->{base});

    my $uri = $self->param('uri');
    my $type =  $self->param('type');
    $DB::single = 1;
    my $node = $ld->my_node($uri);

    my $preds = RDF::LinkedData::Predicates->new($ld->model);

    my $page = $preds->page($node);
    if (($type eq 'page') && ($page ne $node->uri_value . '/page')) {
        # Then, we have a foaf:page set that we should redirect to
        $self->res->code(301);
        $self->res->headers->location($page);
    }

    $log->info("Try rendering $type page for subject node: " . $node->as_string);
    if ($ld->count($node) > 0) {
        $log->debug("Will render $type page for Accept header: " . $self->req->headers->header('Accept'));
        my $h = HTTP::Headers->new(%{$self->req->headers->to_hash});
        $ld->headers_in($h);
        my $content = $ld->content($node, $type);
        $self->res->headers->header('Vary' => join(", ", qw(Accept)));
        $self->res->headers->content_type($content->{content_type});
        $self->render_text($content->{body});
    } else {
        $self->render_not_found;
    }
};

get '/(*relative)' => sub {
    my $self = shift;
    my $ld = RDF::LinkedData->new(config => $config->{store}, base => $config->{base});
    my $node = $ld->my_node('/'.$self->param('relative'));

    $log->info('Subject node: ' . $node->as_string);
    if ($ld->count($node) > 0) {
        $self->res->code(303);
        my $h = HTTP::Headers->new(%{$self->req->headers->to_hash});
        $ld->headers_in($h);
        my $newurl = $self->req->url->to_abs . '/' . $ld->type;
        if ($ld->type eq 'page') {
            my $preds = RDF::LinkedData::Predicates->new($ld->model);
            $newurl = $preds->page($node);
        }
        $log->debug('Will do a 303 redirect to ' . $newurl);
        $self->res->headers->location($newurl);
        $self->res->headers->header('Vary' => join(", ", qw(Accept)));
    } else {
        $self->res->code(404);
        $self->res->headers->content_type('text/plain');
        $self->render_text('HTTP 404: Unknown resource');
    }
};


shagadelic;


__END__

=back

=head1 AUTHOR

Kjetil Kjernsmo  C<< <kjetilk@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2010 ABC Startsiden AS. This program is free software;
you can redistribute it and/or modify it under the same terms as Perl
itself.

=cut
