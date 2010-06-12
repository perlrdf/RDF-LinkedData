package RDF::LinkedData::Predicates;

use warnings;
use strict;

use RDF::Trine;
use RDF::Trine qw(iri variable statement);

use Scalar::Util qw(blessed);

use Error qw(:try);

=head1 NAME

RDF::LinkedData::Predicates - Module that provides shortcuts to retrieve certain information

=head1 VERSION

Version 0.05

=cut

our $VERSION = '0.05';


=head1 SYNOPSIS

    my $pred = RDF::LinkedData::Predicates->new($model);
    print $pred->title


=head1 METHODS

=over

=item C<< new ( $model ) >>

Constructor for getting predicates from a model, which is passed to the constructor.

=cut

sub new {
	my $class = shift;

	my $self = bless( {
                _model  => shift,
		_cache	=> {
			title	=> {
				'<http://www.w3.org/2000/01/rdf-schema#label>'	=> 'label',
				'<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'	=> 'type',
			},
			pred	=> {
				'<http://www.w3.org/2000/01/rdf-schema#label>'	=> 'label',
				'<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'	=> 'type',
				'<http://purl.org/dc/elements/1.1/type>' => 'Type',
			},
		},
	}, $class );
	
	foreach (1 .. 50) {
		$self->{_cache}{pred}{"<http://www.w3.org/1999/02/22-rdf-syntax-ns#_$_>"}	= "#$_";
	}
	
	return $self;
} # END sub new


=item C<< page ( $node ) >>

A suitable page to redirect to, based on foaf:page or foaf:homepage

=cut

sub page {
    my $self	= shift;
    my $node	= shift;
    throw Error -text => "Node argument needs to be a RDF::Trine::Node::Resource." unless ($node && $node->isa('RDF::Trine::Node::Resource'));

    my $model	= $self->{_model};

    my @props	= (
                   iri( 'http://xmlns.com/foaf/0.1/homepage' ),
                   iri( 'http://xmlns.com/foaf/0.1/page' ),
                  );

    # optimistically assume that we'll get back a valid page on the first try
    my $objects	= $model->objects_for_predicate_list( $node, @props );
    if (blessed($objects) && $objects->is_resource) {
        return $objects->uri_value;
    }

    # Return the common link to ourselves
    return $node->uri_value . '/page';
}


=item C<< title ( $node ) >>

A suitable title for the document will be returned, based on document contents

=cut

sub title {
	my $self	= shift;
	my $node	= shift;
	my $nodestr	= $node->as_string;
	if (my $title = $self->{_cache}{title}{$nodestr}) {
		return $title;
	} else {
		my $model	= $self->{_model};

		my @label	= (
			iri( 'http://xmlns.com/foaf/0.1/name' ),
			iri( 'http://purl.org/dc/terms/title' ),
			iri( 'http://purl.org/dc/elements/1.1/title' ),
			iri( 'http://www.w3.org/2000/01/rdf-schema#label' ),
		);
		
		{
			# optimistically assume that we'll get back a valid name on the first try
			my $name	= $model->objects_for_predicate_list( $node, @label );
			if (blessed($name) and $name->is_literal) {
				my $str	= $name->literal_value;
				$self->{_cache}{title}{$nodestr}	= $str;
				return $str;
			}
		}
		
		# if that didn't work, continue to try to find a valid literal title node
		my @names	= $model->objects_for_predicate_list( $node, @label );
		foreach my $name (@names) {
			if ($name->is_literal) {
				my $str	= $name->literal_value;
				$self->{_cache}{title}{$nodestr}	= $str;
				return $str;
			}
		}
		
		# and finally fall back on just returning a string version of the node
		if ($node->is_resource) {
			my $uri	= $node->uri_value;
			$self->{_cache}{title}{$nodestr}	= $uri;
			return $uri;
		} else {
			my $str	= $node->as_string;
			$self->{_cache}{title}{$nodestr}	= $str;
			return $str;
		}
	}
}

=item C<< description ( $node ) >>

A suitable description for the document will be returned, based on document contents

=cut


sub description {
	my $self	= shift;
	my $node	= shift;
	my $model	= $self->{_model};
	
	my $iter	= $model->get_statements( $node );
	my @label	= (
					iri( 'http://www.w3.org/2000/01/rdf-schema#label' ),
#					iri( 'http://purl.org/dc/elements/1.1/description' ),
				);
	my @desc;
	while (my $st = $iter->next) {
		my $p	= $st->predicate;
		
		my $ps;
		if (my $pname = $self->{_cache}{pred}{$p->as_string}) {
			$ps	= $pname;
		} elsif (my $pn = $model->objects_for_predicate_list( $p, @label )) {
			$ps	= $self->html_node_value( $pn );
		} elsif ($p->is_resource and $p->uri_value =~ m<^http://www.w3.org/1999/02/22-rdf-syntax-ns#_(\d+)$>) {
			$ps	= '#' . $1;
		} else {
			# try to turn the predicate into a qname and use the local part as the printable name
			my $name;
			try {
				(my $ns, $name)	= $p->qname;
			} catch RDF::Trine::Error with {};
			if ($name) {
				my $title	= _escape( $name );
				$ps	= $title;
			} else {
				$ps	= _escape( $p->uri_value );
			}
		}
		
		$self->{_cache}{pred}{$p->as_string}	= $ps;
		my $obj	= $st->object;
		my $os	= $self->html_node_value( $obj, $p );
		
		push(@desc, [$ps, $os]);
	}
	return \@desc;
}



=item C<< html_node_value >>

Formats the nodes for HTML output.

=cut


sub html_node_value {
	my $self		= shift;
	my $n			= shift;
	my $rdfapred	= shift;
	my $qname		= '';
	my $xmlns		= '';
	if ($rdfapred) {
		try {
			my ($ns, $ln)	= $rdfapred->qname;
			$xmlns	= qq[xmlns:ns="${ns}"];
			$qname	= qq[ns:$ln];
		} catch RDF::Trine::Error with {};
	}
	return '' unless (blessed($n));
	if ($n->is_literal) {
		my $l	= _escape( $n->literal_value );
		if ($qname) {
			return qq[<span $xmlns property="${qname}">$l</span>];
		} else {
			return $l;
		}
	} elsif ($n->is_resource) {
		my $uri		= _escape( $n->uri_value );
		my $title	= _escape( $self->title( $n ) );
		
		if ($qname) {
			return qq[<a $xmlns rel="${qname}" href="${uri}">$title</a>];
		} else {
			return qq[<a href="${uri}">$title</a>];
		}
	} else {
		return $n->as_string;
	}
}

sub _escape {
	my $l	= shift;
	for ($l) {
		s/&/&amp;/g;
		s/</&lt;/g;
		s/"/&quot;/g;
	}
	return $l;
}


=back


=head1 AUTHOR

Most of the code was written by Gregory Todd Williams C<< <gwilliams@cpan.org> >> for L<RDF::LinkedData::Apache>, but refactored into this class for use by other modules by Kjetil Kjernsmo, C<< <kjetilk at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Gregory Todd Williams and ABC Startsiden AS.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1;
