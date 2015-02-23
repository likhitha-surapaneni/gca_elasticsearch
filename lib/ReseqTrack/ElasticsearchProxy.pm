package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    $self->defaults(format => $self->config('default_format'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }


    $self->routes->get('/:path1/:path2/:path3/:path4')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '', path3 => '', path4 => '');
    $self->routes->options('/:path1/:path2/:path3/:path4')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '', path3 => '', path4 => '');

    $self->routes->get('/*')->to(controller=>'elasticsearch', action=>'bad_request');
    $self->routes->options('/*')->to(controller=>'elasticsearch', action=>'bad_request');

    $self->routes->post('/:path1/:path2/_search')->to(controller=>'elasticsearch', action=>'es_query', path1 => '', path2 => '');

    $self->routes->any('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');

}

1;
