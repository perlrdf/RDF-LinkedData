package RDF::LinkedData;

use namespace::autoclean;

use RDF::Trine qw[iri literal blank statement];
use RDF::Trine::Serializer;
use Log::Log4perl qw(:easy);
use Plack::Response;
use RDF::Helper::Properties;
use URI;
use HTTP::Headers;
use Module::Load::Conditional qw[can_load];
use Moose;
use MooseX::UndefTolerant::Attribute;
use Encode;
use RDF::RDFa::Generator 0.102;
use HTML::HTML5::Writer qw(DOCTYPE_XHTML_RDFA);
use Data::Dumper;

with 'MooseX::Log::Log4perl::Easy';

BEGIN {
	if ($ENV{TEST_VERBOSE}) {
		Log::Log4perl->easy_init( { level   => $TRACE } );
	} else {
		Log::Log4perl->easy_init( { level   => $FATAL } );
	}
}




=head1 NAME

RDF::LinkedData - A simple Linked Data implementation

=head1 VERSION

Version 0.42

=cut

our $VERSION = '0.42';


=head1 SYNOPSIS

For just setting this up and get it to run, you would just use the
C<linked_data.psgi> script in this distribution. The usage of that is documented in
L<Plack::App::RDF::LinkedData>. If you want to try and use this
directly, you'd do stuff like:

	my $ld = RDF::LinkedData->new(store => $config->{store},
                                 endpoint_config => $config->{endpoint},
                                 base_uri => $config->{base_uri}
                                );
	$ld->namespaces($config->{namespaces}) if ($config->{namespaces});
	$ld->request($req);
	return $ld->response($uri)->finalize;

See L<Plack::App::RDF::LinkedData> for a complete example.


=head1 METHODS

=over

=item C<< new ( store => $store, model => $model, base_uri => $base_uri, 
                hypermedia => 1, namespaces_as_vocabularies => 1, 
                request => $request, endpoint_config => $endpoint_config ) >>

Creates a new handler object based on named parameters, given a store
config (recommended usage is to pass a hashref of the type that can be
passed to L<RDF::Trine::Store>->new_with_config, but a simple string
can also be used) or model and a base URI. Optionally, you may pass a
L<Plack::Request> object (must be passed before you call C<content>)
and an C<endpoint_config> hashref if you want to have a SPARQL
Endpoint running using the recommended module L<RDF::Endpoint>.

This module can also provide additional triples to turn the respons
into a hypermedia type. If you don't want this, set the C<hypermedia>
argument to false. Currently this entails setting the SPARQL endpoint
and vocabularies used using the L<VoID vocabulary|http://vocab.deri.ie/void>.
The latter is very limited at present, all it'll do is use the namespaces
if you have C<namespaces_as_vocabularies> enabled, which it is by default.

=item C<< BUILD >>

Called by Moose to initialize an object.

=cut

sub BUILD {
	my $self = shift;

	# A model will be passed or built by the _build_model, so we can check directly if we have one
	unless ($self->model->isa('RDF::Trine::Model')) {
		throw Error -text => "No valid RDF::Trine::Model, need either a store config hashref or a model.";
	}

 	if ($self->has_endpoint_config) {
		$self->logger->debug('Endpoint config found with parameters: ' . Dumper($self->endpoint_config) );

		unless (can_load( modules => { 'RDF::Endpoint' => 0.03 })) {
			throw Error -text => "RDF::Endpoint not installed. Please install or remove its configuration.";
		}
		$self->endpoint(RDF::Endpoint->new($self->model, $self->endpoint_config));
 	} else {
		$self->logger->info('No endpoint config found');
	}
}

has store => (is => 'rw', isa => 'HashRef' );


=item C<< model >>

Returns the RDF::Trine::Model object.

=cut

has model => (is => 'ro', isa => 'RDF::Trine::Model', lazy => 1, builder => '_build_model');

sub _build_model {
	my $self = shift;
	# First, set the base if none is configured
	my $i = 0;
	foreach my $source (@{$self->store->{sources}}) {
		unless ($source->{base_uri}) {
			${$self->store->{sources}}[$i]->{base_uri} = $self->base_uri;
		}
		$i++;
	}
	my $store = RDF::Trine::Store->new( $self->store );
	return RDF::Trine::Model->new( $store );
}


=item C<< base_uri >>

Returns or sets the base URI for this handler.

=cut

has base_uri => (is => 'rw', isa => 'Str', default => '' );

has hypermedia => (is => 'ro', isa => 'Bool', default => 1);

has namespaces_as_vocabularies => (is => 'ro', isa => 'Bool', default => 1);

has endpoint_config => (is => 'rw', traits => [ qw(MooseX::UndefTolerant::Attribute)],
								isa=>'HashRef', predicate => 'has_endpoint_config');


=item C<< request ( [ $request ] ) >>

Returns the L<Plack::Request> object if it exists or sets it if a L<Plack::Request> object is given as parameter.

=cut

has request => ( is => 'rw', isa => 'Plack::Request');


=item C<< etag >>

Returns an Etag suitable for use in a HTTP header

=cut

has etag => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_etag');

sub _build_etag {
	return $_[0]->model->etag;
}



=item namespaces ( { skos => 'http://www.w3.org/2004/02/skos/core#', dct => 'http://purl.org/dc/terms/' } )

Gets or sets the namespaces that some serializers use for pretty-printing.

=cut

has 'namespaces' => (is => 'rw', isa => 'HashRef', default => sub { { rdf => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' } } );



=item C<< response ( $uri ) >>

Will look up what to do with the given URI object and populate the
response object.

=cut

sub response {
	my $self = shift;
	my $uri = URI->new(shift);
	my $response = Plack::Response->new;

	my $headers_in = $self->request->headers;
	my $endpoint_path = '/sparql';
	if ($self->has_endpoint_config && defined($self->endpoint_config->{endpoint_path})) {
      $endpoint_path = $self->endpoint_config->{endpoint_path};
	}

	if ($self->has_endpoint && ($uri->path eq $endpoint_path)) {
      return $self->endpoint->run( $self->request );
	}

	my $type = $self->type;
	$self->type('');
	my $node = $self->my_node($uri);
	$self->logger->info("Try rendering '$type' page for subject node: " . $node->as_string);
	if ($self->count($node) > 0) {
		if ($type) {
			my $preds = $self->helper_properties;
			my $page = $preds->page($node);
			if (($type eq 'page') && ($page ne $node->uri_value . '/page')) {
				# Then, we have a foaf:page set that we should redirect to
				$response->status(301);
				$response->headers->header('Location' => $page);
				return $response;
			}

			$self->logger->debug("Will render '$type' page ");
			if ($headers_in->can('header') && $headers_in->header('Accept')) {
				$self->logger->debug('Found Accept header: ' . $headers_in->header('Accept'));
			} else {
				$headers_in->header(HTTP::Headers->new('Accept' => 'application/rdf+xml'));
				if ($headers_in->header('Accept')) {
					$self->logger->warn('Setting Accept header: ' . $headers_in->header('Accept'));
				} else {
					$self->logger->warn('No content type header can be set');
				}
			}
			$response->status(200);
			my $content = $self->content($node, $type);
			$response->headers->header('Vary' => join(", ", qw(Accept)));
			$response->headers->header('ETag' => $self->etag);
			$response->headers->content_type($content->{content_type});
			$response->content($content->{body});
		} else {
			$response->status(303);
			my ($ct, $s);
			eval {
				($ct, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $headers_in,
                                                          base => $self->base_uri,
                                                          namespaces => $self->namespaces,
																			 extend => {
																							'text/html' => 'html',
																							'application/xhtml+xml' => 'html'
																						  }
																			)
	      };
			$self->logger->debug("Got $ct content type");
			if ($@) {
				$response->status(406);
				$response->headers->content_type('text/plain');
				$response->body('HTTP 406: No serialization available any specified content type');
				return $response;
			}
			my $newurl = $uri . '/data';
			unless ($s->isa('RDF::Trine::Serializer')) {
				my $preds = $self->helper_properties;
				$newurl = $preds->page($node);
			}
			$self->logger->debug('Will do a 303 redirect to ' . $newurl);
			$response->headers->header('Location' => $newurl);
			$response->headers->header('Vary' => join(", ", qw(Accept)));
		}
		return $response;
	} else {
		$response->status(404);
		$response->headers->content_type('text/plain');
		$response->body('HTTP 404: Unknown resource');
		return $response;
	}
	# We should never get here.
	$response->status(500);
	$response->headers->content_type('text/plain');
	$response->body('HTTP 500: No such functionality.');
	return $response;
}


=item C<< helper_properties (  ) >>

Returns the L<RDF::Helper::Properties> object if it exists or sets
it if a L<RDF::Helper::Properties> object is given as parameter.

=cut

has helper_properties => ( is => 'rw', isa => 'RDF::Helper::Properties', lazy => 1, builder => '_build_helper_properties');

sub _build_helper_properties {
	my $self = shift;
	return RDF::Helper::Properties->new(model => $self->model);
}



=item C<< type >>

Returns or sets the type of result to return, i.e. C<page>, in the case of a human-intended page or C<data> for machine consumption, or an empty string if it is an actual resource URI that should be redirected.

=cut

has 'type' => (is => 'rw', isa => 'Str', default => ''); 


=item C<< my_node >>

A node for the requested URI. This node is typically used as the
subject to find which statements to return as data. This expects to
get a URI object containing the full URI of the node.

=cut

sub my_node {
	my ($self, $iri) = @_;
    
	# not happy with this, but it helps for clients that do content sniffing based on filename
	$iri =~ s/.(nt|rdf|ttl)$//;
	$self->logger->info("Subject URI to be used: $iri");
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

One may argue that a hashref with magic keys should be a class of its
own, and for that reason, this method should be considered "at
risk". Currently, it is only used in one place, and it may be turned
into a private method, get passed the L<Plack::Response> object,
removed altogether or turned into a role of its own, depending on the
actual use cases that surfaces in the future.

=cut


sub content {
	my ($self, $node, $type) = @_;
	my $model = $self->model;
	my $iter = $model->bounded_description($node);
	my %output;
	if ($type eq 'data') {
		$self->{_type} = 'data';
		my ($ctype, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $self->request->headers,
																			base => $self->base_uri,
																			namespaces => $self->namespaces);
		$output{content_type} = $ctype;
		if ($self->hypermedia) {
			my $hmmodel = RDF::Trine::Model->temporary_model;
			if($self->has_endpoint) {
				$hmmodel->add_statement(statement(iri($node->uri_value . '/data'), 
															 iri('http://rdfs.org/ns/void#inDataset'), 
															 blank('void')));
				$hmmodel->add_statement(statement(blank('void'), 
															 iri('http://rdfs.org/ns/void#sparqlEndpoint'),
															 iri($self->base_uri . $self->endpoint_config->{endpoint_path})));
			}
			if($self->namespaces_as_vocabularies) {
				$hmmodel->add_statement(statement(iri($node->uri_value . '/data'), 
															 iri('http://rdfs.org/ns/void#inDataset'), 
															 blank('void')));
				foreach my $nsuri (values(%{$self->namespaces})) {
					$hmmodel->add_statement(statement(blank('void'), 
																 iri('http://rdfs.org/ns/void#vocabulary'),
																 iri($nsuri)));
				}
			}
			$iter = $iter->concat($hmmodel->as_stream);
		}
		$output{body} = $s->serialize_iterator_to_string ( $iter );
		$self->logger->trace("Message body is $output{body}");

	} else {
		$self->{_type} = 'page';
		my $returnmodel = RDF::Trine::Model->temporary_model;
		while (my $st = $iter->next) {
			$returnmodel->add_statement($st);
		}
		my $preds = $self->helper_properties;
		my $gen  = RDF::RDFa::Generator->new( style => 'HTML::Pretty',
														  title => $preds->title( $node ),
														  base => $self->base_uri,
														  namespaces => $self->namespaces);
		my $writer = HTML::HTML5::Writer->new( markup => 'xhtml', doctype => DOCTYPE_XHTML_RDFA );
		$output{body} = encode_utf8( $writer->document($gen->create_document($returnmodel)) );
		$output{content_type} = 'text/html';
	}
	return \%output;
}



=item C<< endpoint ( [ $endpoint ] ) >>

Returns the L<RDF::Endpoint> object if it exists or sets it if a
L<RDF::Endpoint> object is given as parameter. In most cases, it will
be created for you if you pass a C<endpoint_config> hashref to the
constructor, so you would most likely not use this method.

=cut


has endpoint => (is => 'rw', isa => 'RDF::Endpoint', predicate => 'has_endpoint');


=back


=head1 AUTHOR

Kjetil Kjernsmo, C<< <kjetilk@cpan.org> >>

=head1 BUGS

Please report any bugs using L<github|https://github.com/kjetilk/RDF-LinkedData/issues>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc RDF::LinkedData

The perlrdf mailing list is the right place to seek help and discuss this module:

L<http://lists.perlrdf.org/listinfo/dev>

=head1 TODO

=over

=item * Use L<IO::Handle> streams when they become available from the serializers.

=item * Figure out what needs to be done to use this code in other frameworks, such as Magpie.

=item * Make it read-write hypermedia.

=item * Use a environment variable for config on the command line?

=back


=head1 ACKNOWLEDGEMENTS

This module was started by Gregory Todd Williams C<<
<gwilliams@cpan.org> >> for L<RDF::LinkedData::Apache>, but has been
almost totally rewritten.

=head1 COPYRIGHT & LICENSE

Copyright 2010 Gregory Todd Williams and ABC Startsiden AS, 2010-2012 Kjetil Kjernsmo

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

# TODO : immutable doesn't seem to work with UndefTolerant
#__PACKAGE__->meta->make_immutable();

1;
