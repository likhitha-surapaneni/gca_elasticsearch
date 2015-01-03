package ReseqTrack::ElasticsearchProxy::Controller;
use Mojo::Base 'Mojolicious::Controller';

sub es_query {
    my ($self) = @_;

    my $es_socket = IO::Socket::INET->new(PeerAddr => 'localhost', PeerPort => 9200);
};
