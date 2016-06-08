package ReseqTrack::ElasticsearchProxy::Plugins::API;
use Mojo::Base qw{ Mojolicious::Plugin };

sub register {
    my ($self, $app, $args) = @_;

    my $api = $app->routes->under('/' => sub {
      my ($controller) = @_;
      API_ROUTE:
      foreach my $api_route (@{$args->{routes}}) {
        my ($api_path, $es_path) = @{$api_route}{qw(from to)};
        next API_ROUTE if !$controller->req->url->path->contains($api_path);
        my $req_path = $controller->req->url->path->to_string;
        $req_path =~ s{^$api_path}{/$es_path/};
        $req_path =~ s{//+}{/}g;
        if ($req_path =~ s/\.(\w+)$//) {
          $controller->stash(format => $1);
        }
        $controller->stash(es_path => $req_path);
        return 1;
      }
    } => {
      es_host => $args->{es_host},
      es_port => $args->{es_port}
    });
    $api->to(controller => 'elasticsearch');
    foreach my $api_route (@{$args->{routes}}) {
      my $api_path = $api_route->{from};
      $api->any(['GET', 'POST'], "$api_path/*whatever" => {whatever => ''})->to(action => 'es_query_router');
      $api->any("$api_path/*whatever")->to(action=>'method_not_allowed');
    }

}

1;
