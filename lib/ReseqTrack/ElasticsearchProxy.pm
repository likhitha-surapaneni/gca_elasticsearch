package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    #$self->defaults(format => $self->config('default_format'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    while (my ($from, $to) = each %{$self->config('plugin_rewrites')}) {
        $self->routes->get($from)->to(controller=>'elasticsearch', action=>'simple', path=>$to);
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
