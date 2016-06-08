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
        es_host => $self->config('elasticsearch_host'),
        es_port => $self->config('elasticsearch_port'),
      );
    }

    my $static_dirs = $self->config('static_directories') || [];
    push @{$self->static->paths}, @$static_dirs;

    $self->plugin('ReseqTrack::ElasticsearchProxy::Plugins::AngularJS',
      angularjs_apps => $self->config('angularjs_apps'),
      angularjs_html5_apps => $self->config('angularjs_html5_apps'),
    );

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
