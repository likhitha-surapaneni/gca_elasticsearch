package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->routes->get('/*')->to(controller=>'elasticsearch', action=>'es_query');
    $self->routes->any('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');

}

1;
