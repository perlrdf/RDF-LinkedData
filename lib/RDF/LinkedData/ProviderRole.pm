package RDF::LinkedData::ProviderRole;

use Moose::Role;

use namespace::autoclean;

use RDF::Trine;
use RDF::Trine::Serializer::NTriples;
use RDF::Trine::Serializer::RDFXML;
use Log::Log4perl;


=head1 NAME

RDF::LinkedData::ProviderRole - Role providing important functionality for Linked Data implementations

=head1 VERSION

Version 0.05

=cut

our $VERSION = '0.05';


=head1 SYNOPSIS

From the L<Mojolicious::Lite> example:

    my $ld = RDF::LinkedData->new($config->{store}, $config->{base});

    my $uri = $self->param('uri');
    my $type =  $self->param('type');
    my $node = $ld->my_node($uri);

    if ($ld->count($node) > 0) {
        my $content = $ld->content($node, $type);
        $self->res->headers->header('Vary' => join(", ", qw(Accept)));
        $self->res->headers->content_type($content->{content_type});
        $self->render_text($content->{body});
    } else {
        $self->render_not_found;
    }


=head1 METHODS

=over

=item C<< new ( config => $config, model => $model, base => $base, headers_in => $headers_in ) >>

Creates a new handler object based on named parameters, given a config
string or model and a base URI. Optionally, you may pass a Apache
request object, and you will need to pass a L<HTTP::Headers> object if
you plan to call C<content>.

=cut

sub BUILD {
	my $self = shift;

        unless($self->model) {
            my $store	= RDF::Trine::Store->new_with_string( $self->config );
            $self->model(RDF::Trine::Model->new( $store ));
	}

        throw Error -text => "No valid RDF::Trine::Model, need either a config string or a model." unless ($self->model);

}


has config => (is => 'rw', isa => 'Str' );


=item C<< headers_in ( [ $headers ] ) >>

Returns the L<HTTP::Headers> object if it exists or sets it if a L<HTTP::Headers> object is given as parameter.

=cut

has headers_in => ( is => 'rw', isa => 'HTTP::Headers');


=item C<< response >>

Returns the L<HTTP::Response> object if it exists or sets it if a L<HTTP::Response> object is given as parameter.

=cut

has response => ( is => 'rw', isa => 'HTTP::Response', builder => '_build_response');

sub _build_response {
    return HTTP::Response->new;
}


=item C<< type >>

Returns the chosen variant based on acceptable formats.

=cut

#requires 'type';

sub type {
    my $self = shift;
    my ($ct, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $self->headers_in);
    return ($ct =~ /rdf|turtle/) ? "data" : "page";
}



=item C<< my_node >>

A node for the requested relative URI. This node is typically used as
the subject to find which statements to return as data. Note that the
base URI, set in the constructor or using the C<base> method, is
prepended to the argument.

=cut

sub my_node {
    my ($self, $first) = @_;
    my $iri	= sprintf( '%s%s', $self->base, $first );
    
    # not happy with this, but it helps for clients that do content sniffing based on filename
    $iri	=~ s/.(nt|rdf|ttl)$//;
    my $l		= Log::Log4perl->get_logger("rdf.linkeddata");    
    $l->trace("Subject URI to be used: $iri");
    return RDF::Trine::Node::Resource->new( $iri );
}

=item C<< count ( $node) >>

Returns the number of statements that has the $node as subject, or all if $node is undef.

=cut


sub count {
    my $self = shift;
    my $node = shift;
    return $self->model->count_statements( $node, undef, undef );
}

=item C<< content ( $node, $type) >>

Will return the a hashref with content for this URI, based on the
$node subject, and the type of node, which may be either C<data> or
C<page>. In the first case, an RDF document serialized to a format set
by content negotiation. In the latter, a simple HTML document will be
returned. The returned hashref has two keys: C<content_type> and
C<body>. The former is self-explanatory, the latter contains the
actual content.

=cut


sub content {
    my ($self, $node, $type) = @_;
    my $model = $self->model;
    my %output;
    if ($type eq 'data') {
        $self->{_type} = 'data';
        my ($type, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $self->headers_in);
        my $iter = $model->bounded_description($node);
        $output{content_type} = $type;
        $output{body} = $s->serialize_iterator_to_string ( $iter );
    } else {
        $self->{_type} = 'page';
        my $preds = RDF::LinkedData::Predicates->new($model);
        my $title		= $preds->title( $node );
        my $desc		= $preds->description( $node );
        my $description	= sprintf( "<table>%s</table>\n", join("\n\t\t", map { sprintf( '<tr><td>%s</td><td>%s</td></tr>', @$_ ) } @$desc) );
        $output{content_type} = 'text/html';
        $output{body} =<<"END";
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML+RDFa 1.0//EN"
	 "http://www.w3.org/MarkUp/DTD/xhtml-rdfa-1.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="content-type" content="text/html; charset=utf-8" />
	<title>${title}</title>
</head>
<body xmlns:foaf="http://xmlns.com/foaf/0.1/">

<h1>${title}</h1>
<hr/>

<div>
	${description}
</div>

</body></html>
END
    }     
    return \%output;
}




=item C<< model >>

Returns or sets the RDF::Trine::Model object.

=cut

has model => (is => 'rw', isa => 'RDF::Trine::Model');

=item C<< base >>

Returns or sets the base URI for this handler.

=cut

has base => (is => 'rw', isa => 'Str', default => "http://localhost:3000" );


=item C<< process ( $uri ) >>

Will look up what to with the given URI and populate the response object.

=cut

sub process {
    my ($self, $uri) = @_;
    my $node = $self->my_node($uri);

    if ($self->type) {
            #die "FOOO: " . $node->to_string;

        if ($self->count($node) > 0) {
            $self->response->code(303);
         #   my $h = HTTP::Headers->new(%{$self->req->headers->to_hash});
         #   $self->headers_in($h);
            my $newurl = $uri . '/' . $self->type;
            if ($self->type eq 'page') {
                my $preds = RDF::LinkedData::Predicates->new($self->model);
                $newurl = $preds->page($node);
            }
            #        $log->debug('Will do a 303 redirect to ' . $newurl);
            $self->response->headers->header('Location' => $newurl);
            $self->response->headers->header('Vary' => join(", ", qw(Accept)));
        } else {
            $self->response->code(404);
            $self->response->headers->content_type('text/plain');
            $self->response->message('HTTP 404: Unknown resource');
        }
        return 1;
    }
    return 0;
}



=back


=head1 AUTHOR

Most of the code was written by Gregory Todd Williams C<< <gwilliams@cpan.org> >> for L<RDF::LinkedData::Apache>, but refactored into this class for use by other modules by Kjetil Kjernsmo, C<< <kjetilk at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-rdf-linkeddata at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=RDF-LinkedData>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc RDF::LinkedData


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=RDF-LinkedData>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/RDF-LinkedData>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/RDF-LinkedData>

=item * Search CPAN

L<http://search.cpan.org/dist/RDF-LinkedData>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2010 Gregory Todd Williams and ABC Startsiden AS.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of RDF::LinkedData
