package ReseqTrack::ElasticsearchProxy::Plugins::AngularJS;
use Mojo::Base qw{ Mojolicious::Plugin };

sub register {
    my ($self, $app, $args) = @_;

    my $angularjs_apps = $args->{angularjs_apps} || [];
    my $angularjs_html5_apps = $args->{angularjs_html5_apps} || [];

    return if !@$angularjs_apps && !$angularjs_html5_apps;

    foreach (@$angularjs_apps, @$angularjs_html5_apps) {
      s{/*$}{/};
      s{^/*}{/};
    }

    foreach my $app_home (@$angularjs_html5_apps) {
      $app->routes->get($app_home.'*' => sub {
        my ($c) = @_;
        return if !$c->accepts('html');
        $c->reply->static($app_home.'index.html');
        $c->res->headers->cache_control('max_age=1, no_cache');
      });
    }

    foreach my $app_home (@{$angularjs_apps}) {
      $app->routes->get($app_home => sub {
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

    $app->hook(after_static => sub {
      my ($c) = @_;
      my $req_path = $c->req->url->path->to_string;
      if (grep {$req_path eq $_.'index.html'} @$angularjs_apps, @$angularjs_html5_apps) {
        return $c->res->headers->cache_control('max_age=1, no_cache');
      }
    });

}

1;
