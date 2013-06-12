#!/usr/bin/perl

use strict;
use warnings;
use Plack::App::RDF::LinkedData;
use RDF::LinkedData;
use Plack::Request;
use Plack::Builder;
use Config::JFDI;
use Carp qw(confess);
use Module::Load::Conditional qw[can_load];

=head1 NAME

linked_data.psgi - A simple Plack server for RDF as linked data

=head1 INSTRUCTIONS

See L<Plack::App::RDF::LinkedData> for instructions on how to use this.

=cut



my $config;
BEGIN {
	$config = Config::JFDI->open( name => "RDF::LinkedData") or confess "Couldn't find config";
}

my $linkeddata = Plack::App::RDF::LinkedData->new();

$linkeddata->configure($config);

my $rdf_linkeddata = $linkeddata->to_app;

builder {
	enable "Head";
	enable "ContentLength";
	enable "ConditionalGET";
	if (can_load( modules => { 'Plack::Middleware::CrossOrigin' => 0 })) { enable 'CrossOrigin' => %{$config->{cors}}};
	enable_if { $linkeddata->auth_required($_[0]) } "Auth::Basic", authenticator => \&authen_cb;
	# TODO: Find clever ways to support other auth modules
	$rdf_linkeddata;
};

sub authen_cb {
    my($username, $password, $env) = @_;
    return $username eq 'testuser' && $password eq 'sikrit';
}
__END__


=head1 AUTHOR

Kjetil Kjernsmo C<< <kjetilk@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2010 ABC Startsiden AS and Gregory Todd Williams and
2010-2013 Kjetil Kjernsmo. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut
