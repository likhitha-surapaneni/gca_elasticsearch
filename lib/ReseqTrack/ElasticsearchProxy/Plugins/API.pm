package ReseqTrack::ElasticsearchProxy::Plugins::API;
use Mojo::Base qw{ Mojolicious::Plugin };

sub register {
    my ($self, $app, $args) = @_;

    foreach my $api_route (@{$args->{routes}}) {
      my ($api_path, $es_path) = @{$api_route}{qw(from to)};
      my $api = $app->routes->under($api_path => sub {
        my ($controller) = @_;
        return undef if !$controller->req->url->path->contains($api_path);
        my $req_path = $controller->req->url->path->to_string;
        $req_path =~ s{^$api_path}{/$es_path/};
        $req_path =~ s{//+}{/}g;
        if ($req_path =~ s/\.(\w+)$//) {
          $controller->stash(format => $1);
        }
        $controller->stash(es_path => $req_path);
        return 1;
      } => {
        es_host => $args->{es_host},
        es_port => $args->{es_port},
      });

      $api->to(controller => 'elasticsearch');
      $api->any(['GET', 'POST'], '/*whatever' => {whatever => ''})->to(action => 'es_query_router');
      $api->any('/*whatever')->to(action=>'method_not_allowed');
    }

}

1;
