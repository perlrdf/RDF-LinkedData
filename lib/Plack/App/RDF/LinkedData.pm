package Plack::App::RDF::LinkedData;
use parent qw( Plack::Component );
use RDF::LinkedData;
use Plack::Request;

sub configure {
	my $self = shift;
	$self->{config} = shift;
	return $self;
}

sub prepare_app {
	my $self = shift;
	my $config = $self->{config};
	$self->{linkeddata} = ($self->{config}->{endpoint})
	  ? RDF::LinkedData->new(store => $config->{store},
									 endpoint_config => $config->{endpoint},
									 base_uri => $config->{base_uri}
									)
		 : RDF::LinkedData->new(store => $config->{store},
										base_uri => $config->{base_uri}
									  );
	$self->{linkeddata}->namespaces($config->{namespaces}) if ($config->{namespaces});
}

sub call {
	my($self, $env) = @_;
	my $req = Plack::Request->new($env);
	my $ld = $self->{linkeddata};
	unless ($req->method eq 'GET') {
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
