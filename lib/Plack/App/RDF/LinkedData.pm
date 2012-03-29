package Plack::App::RDF::LinkedData;
use parent qw( Plack::Component );
use RDF::LinkedData;
use Plack::Request;

=head1 NAME

Plack::App::RDF::LinkedData - A Plack application for running RDF::LinkedData

=head1 SYNOPSIS

  my $linkeddata = Plack::App::RDF::LinkedData->new();
  $linkeddata->configure($config);
  my $rdf_linkeddata = $linkeddata->to_app;

  builder {
     enable "Head";
	  enable "ContentLength";
	  enable "ConditionalGET";
	  $rdf_linkeddata;
  };

=head1 METHODS

=over

=item C<< configure >>

This is the only method you would call manually, as it can be used to
pass a hashref with configuration to the application.

=cut

sub configure {
	my $self = shift;
	$self->{config} = shift;
	return $self;
}


=item C<< prepare_app >>

Will be called by Plack to set the application up.

=item C<< call >>

Will be called by Plack to process the request.

=back

=cut


sub prepare_app {
	my $self = shift;
	my $config = $self->{config};
	$self->{linkeddata} = RDF::LinkedData->new(store => $config->{store},
															 endpoint_config => $config->{endpoint},
															 base_uri => $config->{base_uri}
															);
	$self->{linkeddata}->namespaces($config->{namespaces}) if ($config->{namespaces});
}

sub call {
	my($self, $env) = @_;
	my $req = Plack::Request->new($env);
	my $ld = $self->{linkeddata};
	unless (($req->method eq 'GET') || ($req->method eq 'HEAD')) {
		return [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ];
	}

	my $uri = $req->uri;
	if ($uri->as_iri =~ m!^(.+?)/?(page|data)$!) {
		$uri = URI->new($1);
		$ld->type($2);
	}
	$ld->request($req);
	return $ld->response($uri)->finalize;
}

1;



=head1 AUTHOR

Kjetil Kjernsmo, C<< <kjetilk@cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010-2012 Kjetil Kjernsmo

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut
