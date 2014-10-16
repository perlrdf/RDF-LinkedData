package RDF::LinkedData;

use Moo;
use namespace::autoclean;
use Types::Standard qw(InstanceOf Str Bool Maybe Int HashRef);

use RDF::Trine qw[iri literal blank statement];
use RDF::Trine::Serializer;
use RDF::Trine::Namespace;
use Log::Log4perl qw(:easy);
use Plack::Response;
use RDF::Helper::Properties;
use URI::NamespaceMap;
use URI;
use HTTP::Headers;
use Module::Load::Conditional qw[can_load];
use Encode;
use RDF::RDFa::Generator 0.102;
use HTML::HTML5::Writer qw(DOCTYPE_XHTML_RDFA);
use Data::Dumper;
use Digest::MD5 ('md5_base64');
use Try::Tiny;

with 'MooX::Log::Any';

BEGIN {
	if ($ENV{TEST_VERBOSE}) {
		Log::Log4perl->easy_init( { level   => $TRACE,
											 category => 'RDF.LinkedData' 
										  } );
	} else {
		Log::Log4perl->easy_init( { level   => $FATAL,
											 category => 'RDF.LinkedData' 
										  } );
	}
}




=head1 NAME

RDF::LinkedData - A simple Linked Data server implementation

=head1 VERSION

Version 0.68

=cut

 our $VERSION = '0.68';


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

=head1 DESCRIPTION

This module is used to create a minimal Linked Data server that can
serve RDF data out of an L<RDF::Trine::Model>. It will look up URIs in
the model and do the right thing (known as the 303 dance) and mint
URLs for that, as well as content negotiation. Thus, you can
concentrate on URIs for your things, you need not be concerned about
minting URLs for the pages to serve it.

=head1 METHODS

=over

=item C<< new ( store => $store, model => $model, base_uri => $base_uri, 
                hypermedia => 1, namespaces_as_vocabularies => 1, 
                request => $request, endpoint_config => $endpoint_config, 
                void_config => $void_config ) >>

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

Called by Moo to initialize an object.

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

		unless (defined($self->endpoint_config->{endpoint_path})) {
		  $self->endpoint_config->{endpoint_path} = '/sparql';
		}

		$self->endpoint(RDF::Endpoint->new($self->model, $self->endpoint_config));
 	} else {
		$self->logger->info('No endpoint config found');
	}

 	if ($self->has_void_config) {
		$self->logger->debug('VoID config found with parameters: ' . Dumper($self->void_config) );

		unless (can_load( modules => { 'RDF::Generator::Void' => 0.04 })) {
			throw Error -text => "RDF::Generator::Void not installed. Please install or remove its configuration.";
		}
		my $dataset_uri = (defined($self->void_config->{dataset_uri}))
								  ? $self->void_config->{dataset_uri} 
								  : URI->new($self->base_uri . '#dataset-0')->canonical;
		$self->_last_extvoid_mtime(0);
		$self->void(RDF::Generator::Void->new(inmodel => $self->model, 
														  dataset_uri => $dataset_uri,
														  namespaces_as_vocabularies => $self->void_config->{namespaces_as_vocabularies}));
 	} else {
		$self->logger->info('No VoID config found');
	}
}

sub BUILDARGS {
	my $class = shift;
	my $args;
	while (my ($key, $value) = (shift, shift)) {
		if ($key) {
			if (defined($value)) {
				$args->{$key} = $value;
			}
		} else { last }
	}

	return $args;
}

has store => (is => 'rw', isa => HashRef | Str );


=item C<< model >>

Returns the RDF::Trine::Model object.

=cut

has model => (is => 'ro', isa => InstanceOf['RDF::Trine::Model'], lazy => 1, builder => '_build_model', 
				  handles => { current_etag => 'etag' });

sub _build_model {
	my $self = shift;
	return $self->_load_model($self->store);
}

sub _load_model {
	my ($self, $store_config) = @_;
	# First, set the base if none is configured
	my $i = 0;
	if (ref($store_config) eq 'HASH') {
		foreach my $source (@{$store_config->{sources}}) {
			unless ($source->{base_uri}) {
				${$store_config->{sources}}[$i]->{base_uri} = $self->base_uri;
			}
			$i++;
		}
	}
	my $store = RDF::Trine::Store->new( $store_config );
	return RDF::Trine::Model->new( $store );
}


=item C<< base_uri >>

Returns or sets the base URI for this handler.

=cut

has base_uri => (is => 'rw', isa => Str, default => '' );

has hypermedia => (is => 'ro', isa => Bool, default => 1);

has namespaces_as_vocabularies => (is => 'ro', isa => Bool, default => 1);

has endpoint_config => (is => 'rw',	isa=>Maybe[HashRef], predicate => 'has_endpoint_config');

has void_config => (is => 'rw', isa=>Maybe[HashRef], predicate => 'has_void_config');



=item C<< request ( [ $request ] ) >>

Returns the L<Plack::Request> object if it exists or sets it if a L<Plack::Request> object is given as parameter.

=cut

has request => ( is => 'rw', isa => InstanceOf['Plack::Request']);


=item C<< current_etag >>

Returns the current Etag of the model suitable for use in a HTTP header. This is a read-only attribute.

=item C<< last_etag >>, C<< has_last_etag >>

Returns or sets the last Etag of so that changes to the model can be detected.

=cut

has last_etag => ( is => 'rw', isa => Str, predicate => 'has_last_etag');


=item namespaces ( { skos => 'http://www.w3.org/2004/02/skos/core#', dct => 'http://purl.org/dc/terms/' } )

Gets or sets the namespaces that some serializers use for pretty-printing.

=cut

has 'namespaces' => (is => 'rw', 
							isa => InstanceOf['URI::NamespaceMap'],
							builder => '_build_namespaces',
							lazy => 1,
							handles => {
											'add_namespace_mapping' => 'add_mapping',
											'list_namespaces' => 'list_namespaces'
										  });


sub _build_namespaces {
  my ($self, $ns_hash) = @_;
  return $ns_hash || URI::NamespaceMap->new({ rdf => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' });
}

# Just a temporary compatibility hack
sub _namespace_hashref {
  my $self = shift;
  my %hash;
  foreach my $prefix ($self->namespaces->list_prefixes) {
	 $hash{$prefix} = $self->namespaces->namespace_uri($prefix)->as_string;
  }
  return \%hash;
}

  


=item C<< response ( $uri ) >>

Will look up what to do with the given URI object and populate the
response object.

=cut

sub response {
	my $self = shift;
	my $uri = URI->new(shift);
	my $response = Plack::Response->new;

	my $headers_in = $self->request->headers;

	my $server = "RDF::LinkedData/$VERSION";
	$server .= " " . $response->headers->header('Server') if defined($response->headers->header('Server'));
	$response->headers->header('Server' => $server);

	my $endpoint_path;
	if ($self->has_endpoint) {
	  $endpoint_path = $self->endpoint_config->{endpoint_path};
	  if ($uri->path eq $endpoint_path) {
		 return $self->endpoint->run( $self->request );
	  }
	}

	if ($self->has_void) {
		my $void_resp = $self->_void_content($uri, $endpoint_path);
		return $void_resp if (defined($void_resp));
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
				$headers_in->header('Accept' => 'application/rdf+xml');
				if ($headers_in->header('Accept')) {
					$self->logger->warn('Setting Accept header: ' . $headers_in->header('Accept'));
				} else {
					$self->logger->warn('No content type header can be set');
				}
			}
			$response->status(200);
			my $content = $self->_content($node, $type, $endpoint_path);
			$response->headers->header('Vary' => join(", ", qw(Accept)));
			if (defined($self->current_etag)) {
			  $response->headers->header('ETag' => '"' . md5_base64($self->current_etag . $content->{content_type}) . '"');
			}
			$response->headers->content_type($content->{content_type});
			$response->body(encode_utf8($content->{body}));
		} else {
			$response->status(303);
			my ($ct, $s) = $self->_negotiate($headers_in);
			return $ct if ($ct->isa('Plack::Response')); # A hack to allow for the failed conneg case
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

has helper_properties => ( is => 'rw', isa => InstanceOf['RDF::Helper::Properties'], lazy => 1, builder => '_build_helper_properties');

sub _build_helper_properties {
	my $self = shift;
	return RDF::Helper::Properties->new(model => $self->model);
}



=item C<< type >>

Returns or sets the type of result to return, i.e. C<page>, in the case of a human-intended page or C<data> for machine consumption, or an empty string if it is an actual resource URI that should be redirected.

=cut

has 'type' => (is => 'rw', isa => Str, default => ''); 


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


# =item C<< _content ( $node, $type, $endpoint_path) >>
#
# Private method to return the a hashref with content for this URI,
# based on the $node subject, and the type of node, which may be either
# C<data> or C<page>. In the first case, an RDF document serialized to a
# format set by content negotiation. In the latter, a simple HTML
# document will be returned. Finally, you may pass the endpoint path if
# it is available. The returned hashref has two keys: C<content_type>
# and C<body>. The former is self-explanatory, the latter contains the
# actual content.

sub _content {
	my ($self, $node, $type, $endpoint_path) = @_;
	
	my $model = $self->model;
	my $iter = $model->bounded_description($node);
	my %output;
	if ($type eq 'data') {
		$self->{_type} = 'data';
		my ($ctype, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $self->request->headers,
																			base => $self->base_uri,
																			namespaces => $self->_namespace_hashref);
		$output{content_type} = $ctype;
		if ($self->hypermedia) {
			my $data_iri = iri($node->uri_value . '/data');
			my $hmmodel = RDF::Trine::Model->temporary_model;
			if($self->has_void) {
				$hmmodel->add_statement(statement($data_iri, 
															 iri('http://rdfs.org/ns/void#inDataset'), 
															 $self->void->dataset_uri));
			} else {
				if($self->has_endpoint) {
					$hmmodel->add_statement(statement($data_iri, 
																 iri('http://rdfs.org/ns/void#inDataset'), 
																 blank('void')));
					$hmmodel->add_statement(statement(blank('void'), 
																 iri('http://rdfs.org/ns/void#sparqlEndpoint'),
																 iri($self->base_uri . $endpoint_path)));
				}
				if($self->namespaces_as_vocabularies) {
					$hmmodel->add_statement(statement($data_iri, 
																 iri('http://rdfs.org/ns/void#inDataset'), 
																 blank('void')));
					foreach my $nsuri ($self->list_namespaces) {
						$hmmodel->add_statement(statement(blank('void'), 
																	 iri('http://rdfs.org/ns/void#vocabulary'),
																	 iri($nsuri->uri)));
					}
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
														  namespaces => $self->_namespace_hashref);
		my $writer = HTML::HTML5::Writer->new( charset => 'ascii', markup => 'html' );
		$output{body} = $writer->document($gen->create_document($returnmodel));
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


has endpoint => (is => 'rw', isa => InstanceOf['RDF::Endpoint'], predicate => 'has_endpoint');


=item C<< void ( [ $voidg ] ) >>

Returns the L<RDF::Generator::Void> object if it exists or sets it if
a L<RDF::Generator::Void> object is given as parameter. Like
C<endpoint>, it will be created for you if you pass a C<void_config>
hashref to the constructor, so you would most likely not use this
method.

=cut


has void => (is => 'rw', isa => InstanceOf['RDF::Generator::Void'], predicate => 'has_void');


sub _negotiate {
	my ($self, $headers_in) = @_;
	my ($ct, $s);
	try {
		($ct, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $headers_in,
																	 base_uri => $self->base_uri,
																	 namespaces => $self->_namespace_hashref,
																	 extend => {
																					'text/html' => 'html',
																					'application/xhtml+xml' => 'xhtml'
																				  }
																	);
		$self->logger->debug("Got $ct content type");
		1;
	} catch {
		my $response = Plack::Response->new;
		$response->status(406);
		$response->headers->content_type('text/plain');
		$response->body('HTTP 406: No serialization available any specified content type');
		return $response;
	};
	return ($ct, $s)
}

sub _void_content {
	my ($self, $uri, $endpoint_path) = @_;
	my $generator = $self->void;
	my $dataset_uri = URI->new($generator->dataset_uri);
	my $fragment = $dataset_uri->fragment;
	$dataset_uri =~ s/(\#$fragment)$//;
	if ($uri->eq($dataset_uri)) {

		# First check if the model has changed, the etag will have
		# changed, and we will have to regenerate at some point. If
		# there is no current etag, we clear anyway
		if ((! defined($self->current_etag)) || ($self->has_last_etag && ($self->last_etag ne $self->current_etag))) {
			$self->_clear_voidmodel; 
		}

		# First see if we should read some static stuff from file
		my $file_model = undef;
		if ($self->void_config->{add_void}) {
			$self->_current_extvoid_mtime((stat($self->void_config->{add_void}->{file}))[9]);
			if ($self->_current_extvoid_mtime != $self->_last_extvoid_mtime) {
				$self->_clear_voidmodel;
				$file_model = RDF::Trine::Model->temporary_model;
				my $parser = RDF::Trine::Parser->new($self->void_config->{add_void}->{syntax});
				$parser->parse_file_into_model($self->base_uri, $self->void_config->{add_void}->{file}, $file_model);
				$self->_last_extvoid_mtime((stat($self->void_config->{add_void}->{file}))[9]);
			}
		}



		# Now really regenerate if there is no model now
	   unless ($self->_has_voidmodel) {

			# Use the methods of the generator to add stuff from config, etc
			if ($self->void_config->{urispace}) {
				$generator->urispace($self->void_config->{urispace});
			} else {
				$generator->urispace($self->base_uri);
			}
			if ($self->namespaces_as_vocabularies) {
			  foreach my $nsuri ($self->list_namespaces) {
				 $generator->add_vocabularies($nsuri->as_string); # TODO: Should be fixed in RDF::Generator::Void, but we fix it here for now
			  }
			}
			if ($self->has_endpoint) {
				$generator->add_endpoints($self->base_uri . $endpoint_path);
			}
			if ($self->void_config->{licenses}) {
				$generator->add_licenses($self->void_config->{licenses});
			}
			foreach my $title (@{$self->void_config->{titles}}) {
				$generator->add_titles(literal(@{$title}));
			}
			if ($self->void_config->{endpoints}) {
				$generator->add_endpoints($self->void_config->{endpoints});
			}
			if ($self->void_config->{vocabularies}) {
				$generator->add_vocabularies($self->void_config->{vocabularies});
			}

			# Do the stats and statements
			$self->_voidmodel($generator->generate($file_model));
			$self->last_etag($self->current_etag);
		}

		# Now start serializing.
		my ($ct, $s) = $self->_negotiate($self->request->headers);
		return $ct if ($ct->isa('Plack::Response')); # A hack to allow for the failed conneg case
		my $body;
		if ($s->isa('RDF::Trine::Serializer')) { # Then we just serialize since we have a serializer.
			$body = $s->serialize_model_to_string($self->_voidmodel);
		} else {
			# For (X)HTML, we need to do extra work
			my $gen = RDF::RDFa::Generator->new( style => 'HTML::Pretty',
															 title => $self->void_config->{pagetitle} || 'VoID Description',
															 base => $self->base_uri,
															 namespaces => $self->_namespace_hashref);
			my $markup = ($ct eq 'application/xhtml+xml') ? 'xhtml' : 'html';
			my $writer = HTML::HTML5::Writer->new( charset => 'ascii', markup => $markup );
			$body = $writer->document($gen->create_document($self->_voidmodel));
		}
		my $response = Plack::Response->new;
		$response->status(200);
		$response->headers->header('Vary' => join(", ", qw(Accept)));
		my $etag;
		$etag = $self->_last_extvoid_mtime if ($self->void_config->{add_void});
		$etag .= $self->last_etag if (defined($self->last_etag));
		if ($etag) {
		  $response->headers->header('ETag' => '"' . md5_base64($etag . $ct) . '"');
		}
		$response->headers->content_type($ct);
		$response->body(encode_utf8($body));
		return $response;
	} else {
		return;
	}
}

has _voidmodel => (is => 'rw', isa => InstanceOf['RDF::Trine::Model'], predicate => '_has_voidmodel', clearer => '_clear_voidmodel');

has _current_extvoid_mtime => (is => 'rw', isa => Int);

has _last_extvoid_mtime => (is => 'rw', isa => Int);


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

=item * Make the result graph configurable.

=back


=head1 ACKNOWLEDGEMENTS

This module was started by Gregory Todd Williams C<<
<gwilliams@cpan.org> >> for L<RDF::LinkedData::Apache>, but has been
almost totally rewritten.

=head1 COPYRIGHT & LICENSE

Copyright 2010 Gregory Todd Williams

Copyright 2010 ABC Startsiden AS

Copyright 2010, 2011, 2012, 2013, 2014 Kjetil Kjernsmo

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

# TODO : immutable doesn't seem to work with UndefTolerant
#__PACKAGE__->meta->make_immutable();

1;
