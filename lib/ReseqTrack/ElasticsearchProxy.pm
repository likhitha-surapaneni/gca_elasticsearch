package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
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

    my $static_dirs = $self->config('static_directories') || [];
    push @{$self->static->paths}, @$static_dirs;

    my $angularjs_apps = $self->config('angularjs_apps') || [];
    my $angularjs_html5_apps = $self->config('angularjs_html5_apps') || [];
    foreach (@$angularjs_apps, @$angularjs_html5_apps) {
      s{/*$}{/};
      s{^/*}{/};
    }

    foreach my $app_home (@$angularjs_html5_apps) {
      $self->routes->get($app_home.'*' => sub {
        my ($c) = @_;
        return if !$c->accepts('html');
        $c->reply->static($app_home.'index.html');
        $c->res->headers->cache_control('max_age=1, no_cache');
      });
    }

    foreach my $app_home (@{$angularjs_apps}) {
      $self->routes->get($app_home => sub {
        my ($c) = @_;
        return if !$c->accepts('html');
        my $req_path = $c->req->url->path;
        if (!$req_path->trailing_slash) {
          $c->res->code(301);
          $req_path->trailing_slash(1);
          return $c->redirect_to($req_path->to_string);
        }
        $c->reply->static($app_home.'index.html');
        $c->res->headers->cache_control('max_age=1, no_cache');
      });
    }

    if (@$angularjs_apps || @$angularjs_html5_apps) {
      $self->hook(after_static => sub {
        my ($c) = @_;
        my $req_path = $c->req->url->path->to_string;
        if (grep {$req_path eq $_.'index.html'} @$angularjs_apps, @$angularjs_html5_apps) {
          return $c->res->headers->cache_control('max_age=1, no_cache');
        }
      });
    }

    $self->routes->get('/*whatever' => {whatever => ''} => sub {
      my ($c) = @_;
      return if !$c->accepts('html');
      $c->reply->static($c->stash('whatever') . '/index.html');
    });



    if (my $redirect_file = $self->config('redirect_file')) {
        $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::Redirect', file => $redirect_file);
    }


}

1;
