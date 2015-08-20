package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    my $static_dirs = $self->config('static_directories') || [];
    foreach my $static_dir_options (@$static_dirs) {
        $self->plugin('Directory', root => $static_dir_options->{dir}, dir_index => 'index.html',
            handler => sub {
                my ($controller, $path) = @_;
                if ($path =~ /\/index.html/) {
                    if ($static_dir_options->{trailing_slash}) {
                        # permanent redirect to put a trailing slash on directories
                        my $req_path = $controller->req->url->path;
                        if ($controller->req->url->path->to_abs_string !~ /\/index.html/ && !$req_path->trailing_slash) {
                            $controller->res->code(301);
                            $req_path->trailing_slash(1);
                            return $controller->redirect_to($req_path->to_abs_string);
                        }
                    }
                    if ($static_dir_options->{no_cache}) {
                        # No caching allowed on index files in the static directory
                        $controller->res->headers->cache_control('max-age=1, no-cache');
                    }
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
