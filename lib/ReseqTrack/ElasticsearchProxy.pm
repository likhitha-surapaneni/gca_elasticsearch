package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    foreach my $path (@{$self->config('allowed_es_plugins'}) {
        $self->routes->get($path)->to(controller=>'elasticsearch', action=>'simple');
    }

    $self->routes->any('/_*')->to(controller=>'elasticsearch', action=>'bad_request');
    $self->routes->get('/*')->to(controller=>'elasticsearch', action=>'es_query');
    $self->routes->options('/*')->to(controller=>'elasticsearch', action=>'es_query');

    $self->routes->post('/:path1/:path2/_search')->to(controller=>'elasticsearch', action=>'es_query');

    $self->routes->post('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');
    $self->routes->put('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');
    $self->routes->delete('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');

}

1;
