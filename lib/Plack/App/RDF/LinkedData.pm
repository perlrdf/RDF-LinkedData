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
        my $store = RDF::Trine::Store->new($self->{config});
        my $model = RDF::Trine::Model->new($store);
        $self->{linkeddata} = RDF::LinkeDdata->new(model => $model);
}

sub call {
        my($self, $env) = @_;
        my $req = Plack::Request->new($env);
        $self->{linkeddata}->init($req->headers, $req->uri);
        my $res;
	  }

1;
