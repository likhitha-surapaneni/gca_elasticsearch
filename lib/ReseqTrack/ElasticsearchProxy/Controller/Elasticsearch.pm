package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';

sub es_query {
    my ($self) = @_;

    $self->es_proxy_helpers->build_es_transaction();

    $self->respond_to(
        json => sub {$self->es_query_json()},
        csv => sub {$self->es_query_tab('csv')},
        tsv => sub {$self->es_query_tab('tsv')},
        any => {data => '', status => 406},
    );
}

sub es_query_json {
    my ($self) = @_;
    my $es_tx = $self->stash('es_tx');
    my $es_user_agent = $self->stash('es_user_agent');

    $es_tx->res->content->on(body => sub {
        $self->res->headers->from_hash($es_tx->res->headers->to_hash);
        $self->res->code($es_tx->res->code);
    });
    $es_tx->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        $self->write($bytes => sub {$es_user_agent->ioloop->start});
        $es_user_agent->ioloop->stop;
    });
    $es_tx->on(finish => sub {
        my ($es_tx) = @_;
        $self->finish;
    });
    if ($self->req->is_finished) {
            $es_tx->req->body($self->req->body);
            $es_user_agent->start($es_tx);
    }
    else {
        $self->req->on(finish => sub {
            $es_tx->req->body($self->req->body);
            $es_user_agent->start($es_tx);
        });
    }
}

sub es_query_tab {
    my ($self, $format) = @_;
    my $es_tx = $self->stash('es_tx');
    my $es_user_agent = $self->stash('es_user_agent');
    $self->app->log->debug("format is $format");
    $self->es_proxy_helpers->setup_json_parsers($format);
    my $json_parser_params = $self->cache->{'json_parser_params'};
    my $length_written = 0;

    $es_tx->res->content->on(body => sub {
        my $headers = $es_tx->res->headers->to_hash;
        delete $headers->{'Content-Length'};
        $self->res->headers->from_hash($headers);
        $self->res->headers->content_type($format eq 'csv' ? 'text/csv' : 'text/tab-separated-values');
        $self->res->code($es_tx->res->code);
        if (! $self->res->is_status_class(200)) {
          $es_tx->res->content->unsubscribe('read');
        }
    });
    $es_tx->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        $json_parser_params->{reader}->feed_buffer(\$bytes);
        return if !$json_parser_params->{lines_to_write};
        {
            use bytes;
            $length_written += length($json_parser_params->{lines_to_write});
        }
        $self->write($json_parser_params->{lines_to_write} => sub {$es_user_agent->ioloop->start});
        $json_parser_params->{lines_to_write} = '';
        $es_user_agent->ioloop->stop;
    });

    $es_tx->on(finish => sub {
        my ($es_tx) = @_;
        $json_parser_params->{reader}->signal_eof;
        {
            use bytes;
            $length_written += length($json_parser_params->{lines_to_write});
        }
        $self->write($json_parser_params->{lines_to_write});
        $self->res->headers->content_length($length_written);
        $self->finish;
    });

    if ($self->req->is_finished) {
        $self->es_proxy_helpers->process_csv_request();
    }
    else {
        $self->req->on(finish => sub {$self->es_proxy_helpers->process_csv_request()});
    }


};

sub bad_request {
    my ($self) = @_;
    my $url_path = $self->req->url->path;
    my $method = $self->req->method;
    my $text = "No handler found for uri [$url_path] and method [$method]";
    $self->render(text => $text, status => 400);
}

sub method_not_allowed {
    my ($self) = @_;
    $self->res->headers->allow('GET', 'HEAD', 'OPTIONS');
    $self->render(text => '', status => 405);
}

1;
