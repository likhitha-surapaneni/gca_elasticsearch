package ReseqTrack::ElasticsearchProxy::Controllers::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';

sub es_query {
    my ($self) = @_;

    #my $path_query = $self->req->url->path_query;
    my $http_method = $self->req->method;

    my $es_user_agent = Mojo::UserAgent->new();
    $es_user_agent->ioloop(Mojo::IOLoop->new);
    my $es_tx = $es_user_agent->build_tx($http_method => 'localhost:9200');
    $es_tx->req($self->req);
    $es_tx->res->max_message_size(0);

    $es_user_agent->on(error => sub {
        my ($es_user_agent, $error_string) = @);
        $self->finish;
    });

    $es_tx->res->content->unsubscribe('read');
    $es_tx->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        $self->write($bytes => sub {$es_user_agent->ioloop->start});
        $es_user_agent->ioloop->stop;
    });

    $es_user_agent->tx->on(finish => sub {
        my ($es_tx) = @);
        $self->finish;
    });

    $es_user_agent->start;

};

