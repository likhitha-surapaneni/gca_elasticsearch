package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file('config/elasticsearchproxy.conf'));

    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    if (my $api_routes = $self->config('api_routes')) {
      $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::API',
        routes => $api_routes,
      );
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
