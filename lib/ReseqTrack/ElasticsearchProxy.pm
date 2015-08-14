package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }
    if (my $static_directory = $self->config('static_directory')) {
        $self->plugin('Directory', root => $static_directory);
    }

    if ($self->config('es_rewrite_rules')) {
        $self->hook('before_dispatch' => sub {
            my ($controller) = @_;
            return if $controller->req->headers->header('X-Forwarded-Server');
            my $es_rewrite_rules = $controller->app->config('es_rewrite_rules');
            my $req_path = $controller->req->url->path->to_abs_string;
            while (my ($from, $to) = each %$es_rewrite_rules) {
                if ($req_path =~ s/^$from/$to/) {
                    $controller->req->url->path->parse($req_path);
                    return;
                }
            }
        });
    }

    foreach my $path (@{$self->config('allowed_es_plugins')}) {
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
