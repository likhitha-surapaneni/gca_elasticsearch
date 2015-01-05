package ReseqTrack::ElasticsearchProxy::ElasticsearchProxy; 
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->routes->any('/*')->to(controller=>'elasticsearch', action=>'es_query');

}

1;
