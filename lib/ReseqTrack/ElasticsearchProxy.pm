package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    # No caching allowed on index files in the static directory
    if (my $static_directory = $self->config('static_directory')) {
        $self->plugin('Directory', root => $static_directory, dir_index => 'index.html',
            handler => sub {
                my ($controller, $path) = @_;
                if ($path =~ /\/index.html/) {
                    $controller->res->headers->cache_control('max-age=1, no-cache');
                }
            },
        );
    }


    my $api_routes = $self->config('api_routes');
    while (my ($api_path, $es_path) = each %$api_routes) {
        my $api = $self->routes->under($api_path => sub {
            my ($controller) = @_;
            my $req_path = $controller->req->url->path->to_abs_string;
            $req_path =~ s/^$api_path/$es_path/;
            $req_path =~ s{//}{/}g;
            if ($req_path =~ /\.(\w+)$/) {
                my $format = $1;
                $req_path =~ s/\.$format$//;
                $controller->stash(format => $format);
            }
            $controller->stash(es_path => $req_path);
        });
        $api->to(controller => 'elasticsearch');

        $api->get('/*')->to(action=>'es_query');
        $api->post('/*')->to(action=>'es_query');
        $api->options('/*')->to(action=>'es_query');
        $api->put('/*')->to(action=>'method_not_allowed');
        $api->delete('/*')->to(action=>'method_not_allowed');
    }

}

1;
