package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';

sub es_query {
    my ($self) = @_;

    my $path_query = $self->req->url->path_query;
    my $http_method = $self->req->method;

    my $es_user_agent = Mojo::UserAgent->new();
    $es_user_agent->ioloop(Mojo::IOLoop->new);
    my $es_tx = $es_user_agent->build_tx($http_method => 'localhost:9200'.$path_query);
    $es_tx->req->headers($self->req->headers);
    $es_tx->req->body($self->req->body);
    $es_tx->res->max_message_size(0);

    $es_user_agent->on(error => sub {
        my ($es_user_agent, $error_string) = @_;
        $self->finish;
    });

    my $have_sent_headers = 0;
    $es_tx->res->content->unsubscribe('read');
    $es_tx->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        if (!$have_sent_headers) {
            $self->res->headers->from_hash($es_tx->res->headers->to_hash);
            $have_sent_headers = 1;
        }
        $self->write($bytes => sub {$es_user_agent->ioloop->start});
        $es_user_agent->ioloop->stop;
    });

    $es_tx->on(finish => sub {
        my ($es_tx) = @_;
        $es_user_agent->ioloop->stop;
        $self->finish;
    });

    $es_user_agent->start($es_tx);

};

sub method_not_allowed {
    my ($self) = @_;
    $self->res->headers->allow('GET', 'HEAD');
    $self->render(text => '', status => 405);
}

1;
