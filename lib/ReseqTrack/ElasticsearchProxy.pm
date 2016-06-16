package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->plugin('Config', file => $self->home->rel_file($ENV{MOJO_CONF} || 'config/elasticsearchproxy.conf'));

    if (my $log_file = $self->config('log_file')) {
      $self->log->path($log_file);
    }

    # Enable cross-origin research sharing
    # Read more about it: https://en.wikipedia.org/wiki/Cross-origin_resource_sharing
    # Good for a sharable API
    if ($self->config('cors.enabled')) {
        $self->plugin('CORS');
    }

    # This plugin does all the routing for the elasticsearch API
    if (my $api_routes = $self->config('api_routes')) {
      $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::API',
        routes => $api_routes,
        es_host => $self->config('elasticsearch_host'),
        es_port => $self->config('elasticsearch_port'),
      );
    }

    # Files in these static directories will get served directly
    if (my $static_dirs = $self->config('static_directories')) {
      push @{$self->static->paths}, @$static_dirs;
    }

    # Files in these directories become templates
    #e.g. exception.production.html.ep not_found.production.html.ep
    if (my $template_dirs = $self->config('template_directories')) {
      push @{$self->renderer->paths}, @$template_dirs;
    }

    # This plugin makes sure angularjs apps are routed correctly
    # It makes sure index.html files are not cached.
    # use the angularjs_html5_apps array if the app uses angularjs option $location.html5Mode(true)
    # otherwise use the angularjs_apps array
    $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::AngularJS',
      angularjs_apps => $self->config('angularjs_apps'),
      angularjs_html5_apps => $self->config('angularjs_html5_apps'),
    );

    # This is to make sure paths matching a directory serve the index.html file
    $self->routes->get('/*whatever' => {whatever => ''} => sub {
      my ($c) = @_;
      return if !$c->accepts('html');
      $c->reply->static($c->stash('whatever') . '/index.html');
    });

    # This is plugin reads a tab-delimited list of paths to redirect
    # First column is "from", second column is "to"
    # File is read every five minutes on a timer in case the file is updated
    if (my $redirect_file = $self->config('redirect_file')) {
        $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::Redirect', file => $redirect_file);
    }


}

1;
