package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    if (my $static_directory = $self->config('static_directory')) {
        $self->plugin('Directory', root => $static_directory, dir_index => 'index.html',
            handler => sub {
                my ($controller, $path) = @_;
                $controller->app->log->info("path is $path");
            },
        );
    }

    my @api_routes;
    push(@api_routes, $self->routes->under('/api' => sub {
        my ($controller) = @_;
        my $req_path = $controller->req->url->path->to_abs_string;
        $req_path =~ s{^/api/}{/};
        $controller->stash(es_path => $req_path);
    }));
    push(@api_routes, $self->routes->under('/lines/api' => sub {
        my ($controller) = @_;
        my $req_path = $controller->req->url->path->to_abs_string;
        $req_path =~ s{^/lines/api/}{/hipsci/};
        $controller->stash(es_path => $req_path);
    }));


    foreach my $api (@api_routes) {
        $api->to(controller => 'elasticsearch');

        $api->get('/*')->to(action=>'es_query');
        $api->post('/*')->to(action=>'es_query');
        $api->options('/*')->to(action=>'es_query');
        $api->put('/*')->to(action=>'method_not_allowed');
        $api->delete('/*')->to(action=>'method_not_allowed');
    }

}

1;
