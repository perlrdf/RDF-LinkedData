package RDF::LinkedData;


use Moose;

with 'RDF::LinkedData::ProviderRole';


=head1 NAME

RDF::LinkedData - Base class for Linked Data implementations

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';


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


=cut



=back


=head1 AUTHOR

Most of the code was written by Gregory Todd Williams C<< <gwilliams@cpan.org> >> for L<RDF::LinkedData::Apache>, but refactored into this class for use by other modules by Kjetil Kjernsmo, C<< <kjetilk at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-rdf-linkeddata at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=RDF-LinkedData>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 WARNING

Do not rely in the current API unless you are planning to keep track
of the development of this module. It is still very much in flux, and
may change without warning!



=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc RDF::LinkedData

The perlrdf mailing list is the right place to seek help and discuss this module:

L<http://lists.perlrdf.org/listinfo/dev>

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

__PACKAGE__->meta->make_immutable;

1; # End of RDF::LinkedData
