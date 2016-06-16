package ReseqTrack::ElasticsearchProxy::Plugins::API;
use Mojo::Base qw{ Mojolicious::Plugin };

sub register {
    my ($self, $app, $args) = @_;

    # replace the incoming reqest path with a real elasticsearch
    # path, so that we can use it for routing
    $app->hook(before_routes => sub {
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
        $controller->stash(es_host => $args->{es_host});
        $controller->stash(es_port => $args->{es_port});
        $controller->req->url->path($req_path);
        return 1;
      }
      return 1;
    });


    $app->routes->add_condition(has_es_path => sub {
      my ($route, $controller, $captures) = @_;
      return $controller->stash('es_path');
    });

    my $api = $app->routes->route('/')->over('has_es_path')
      ->to(controller => 'elasticsearch');

    # Allow use of the scroll API and of our testpage plugin.
    # ...but disallow anything else starting with '_'
    $api->get('/_plugin/testpage')->to(action => 'es_query_direct');
    $api->any(['GET', 'POST'] => '/_search/scroll')->to(action => 'es_query_direct');
    $api->any('/_*whatever' => {whatever => ''})->to(action => 'method_not_allowed');

    # Allow the _mapping API e.g. /hipsci/_mapping/donor
    # ...but disallow paths like e.g. /hipsci/_flush or /hipsci/_settings
    $api->get('/:index/_mapping/:type')->to(action => 'es_query_direct');
    $api->any('/:index/_*whatever' => {whatever => ''})->to(action => 'method_not_allowed');

    # allow _search, but let the search router work out how to handle it
    $api->any(['GET', 'POST'] => '/:index/:type/_search/*whatever' => {whatever => ''})->to(action => 'es_search_router');

    # allow _count and _validate APIs
    # ...but disallow aything else with an underscore in 3rd position
    $api->any(['GET', 'POST'] => '/:index/:type/_count/*whatever' => {whatever => ''})->to(action => 'es_query_direct');
    $api->any(['GET', 'POST'] => '/:index/:type/_validate/*whatever' => {whatever => ''})->to(action => 'es_query_direct');
    $api->any('/:index/:type/_*whatever' => {whatever => ''})->to(action => 'method_not_allowed');

    # allow _count and _validate APIs
    # ...but disallow aything else with an underscore in 4th position
    $api->get('/:index/:type/:id/_mlt/*whatever' => {whatever => ''})->to(action => 'es_query_direct');
    $api->any('/:index/:type/:id/_*whatever' => {whatever => ''})->to(action => 'method_not_allowed');

    # all other paths are safe e.g. /hipsci/donor/name
    $api->any(['GET', 'POST'] => '/:index/:type/:name/*whatever' => {whatever => ''})->to(action => 'es_query_direct');
    $api->any('/*whatever' => {whatever => ''})->to(action => 'method_not_allowed');

}

1;
