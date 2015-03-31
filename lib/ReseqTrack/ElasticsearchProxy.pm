package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    $self->defaults(format => $self->config('default_format'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    $self->routes->get('/:webapp')->to(controller=>'static', action=>'webapp_index');

    $self->routes->get('/api/:path1/:path2/:path3/:path4')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '', path3 => '', path4 => '');
    $self->routes->options('/api/:path1/:path2/:path3/:path4')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '', path3 => '', path4 => '');

    $self->routes->get('/api/*')->to(controller=>'elasticsearch', action=>'bad_request');
    $self->routes->options('/api/*')->to(controller=>'elasticsearch', action=>'bad_request');

    $self->routes->post('/api/:path1/:path2/_search')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '');

    $self->routes->get('/:name')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '');

    $self->routes->post('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');
    $self->routes->put('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');
    $self->routes->delete('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');

}

1;
