package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';
use ReseqTrack::ElasticsearchProxy::Model::JSONParsers;
use ReseqTrack::ElasticsearchProxy::Model::ESTransaction;
use JSON;

sub es_query {
    my ($self) = @_;

    my $es_path = $self->stash('es_path');
    my @es_path_parts = split('/', $es_path);
    if ($es_path_parts[0] =~ /^_/) {
        return $self->bad_request();
    }
    if ($self->req->method eq 'POST') {
        if (scalar @es_path_parts != 3 || $es_path_parts[2] !~ /^_search(\.\w*)?$/) {
            $self->app->log->info(join('  |  ' @es_path_parts));
            return $self->method_not_allowed();
        }
    }
    if ($es_path eq /test/) {
        $self->simple('/_plugin/testpage');
    }

    $self->respond_to(
        csv => sub {$self->es_query_tab($es_path, 'csv')},
        tsv => sub {$self->es_query_tab($es_path, 'tsv')},
        any => sub {$self->es_query_default($es_path)},
    );
}

sub simple {
    my ($self, $es_path) = @_;

    my $es_host = $self->app->config('elasticsearch_host');
    my $es_port = $self->app->config('elasticsearch_port');
    my $url = "http://$es_host:$es_port$es_path";

    $self->ua->get($url => sub {
        my ($ua, $tx) = @_;
        $self->res->headers->from_hash($tx->res->headers->to_hash);
        $self->res->code($tx->res->code);
        $self->write($tx->res->body => sub {
          $self->finish;
        });
    });

}

sub es_query_default {
    my ($self, $es_path) = @_;
    my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
        port => $self->app->config('elasticsearch_port'),
        host => $self->app->config('elasticsearch_host'),
        method => $self->req->method,
        url_path => $es_path,
    );
    $es_transaction->set_headers($self->req->headers);
    $es_transaction->errors_callback(sub {$self->finish});

    $es_transaction->headers_callback( sub {
        my ($es_headers, $es_code) = @_;
        $self->res->headers->from_hash($es_headers);
        $self->res->code($es_code);
    });
    $es_transaction->partial_content_callback( sub {
        my ($bytes) = @_;
        $self->write($bytes => sub {$es_transaction->resume});
        $es_transaction->pause;
    });
    $es_transaction->finished_callback( sub {$self->finish});
    if ($self->req->is_finished) {
        $es_transaction->set_body($self->req->body);
        $es_transaction->start;
    }
    else {
        $self->req->on(finish => sub {
            $es_transaction->set_body($self->req->body);
            $es_transaction->start;
        });
    }
}

sub es_query_tab {
    my ($self, $es_path, $format) = @_;
    $es_path =~ s{\.$format$}{};
    my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
        port => $self->app->config('elasticsearch_port'),
        host => $self->app->config('elasticsearch_host'),
        method => $self->req->method,
        url_path => $es_path,
    );
    $self->app->log->debug("format is $format");
    my $json_parser = ReseqTrack::ElasticsearchProxy::Model::JSONParsers->new(format => $format);

    $es_transaction->headers_callback( sub {
        my ($es_headers, $es_code) = @_;
        if ($es_code <200 || $es_code >=300) {
            $self->render('', $es_code);
        }
        delete $es_headers->{'Content-Length'};
        $self->res->headers->from_hash($es_headers);
        $self->res->headers->content_type($format eq 'csv' ? 'text/csv' : 'text/tab-separated-values');
        $self->res->code($es_code);
    });
    $es_transaction->partial_content_callback( sub {
        my ($bytes) = @_;
        $json_parser->reader->feed_buffer(\$bytes);
        return if !$json_parser->has_lines_to_write;
        $self->write(${$json_parser->give_lines_to_write} => sub {$es_transaction->resume});
        $es_transaction->pause;
    });

    $es_transaction->finished_callback( sub {
        $json_parser->reader->signal_eof;
        if ($json_parser->has_lines_to_write) {
            $self->write(${$json_parser->give_lines_to_write});
        }
        $self->res->headers->content_length($json_parser->bytes_produced);
        $self->finish;
    });

    if ($self->req->is_finished) {
        $self->process_request_for_tab($self->req, $json_parser, $es_transaction);
    }
    else {
        $self->req->on(finish => sub {
            $self->process_request_for_tab($self->req, $json_parser, $es_transaction);
        });
    }

};

sub process_request_for_tab {
    my ($self, $req, $json_parser, $es_transaction) = @_;
    my $req_body;
    if ($req->headers->content_type eq 'application/x-www-form-urlencoded') {
        my $json = $req->body_params->to_hash->{json};
        if (!$json) {
            $self->render(text => 'www-form did not contain json', status => 400);
            return;
        }
        eval { $req_body = JSON::decode_json($json); };
        if ($@) {
            $self->render(text => 'error encoutered while parsing JSON', status => 400);
            return;
        }
    }
    else {
        eval { $req_body = JSON::decode_json($req->body); };
        if ($@) {
            $self->render(text => 'error encoutered while parsing JSON', status => 400);
            return;
        }
    }
    if (! $req_body->{fields}) {
        $self->render(text => 'request body does not give "fields"', status => 400);
        return;
    }
    eval {$json_parser->fields($req_body->{fields})};
    if ($@) {
        $self->render(text => '"fields" format was not valid', status => 400);
        return;
    }
    eval {$json_parser->column_names($req_body->{column_names} // $req_body->{fields})};
    if ($@) {
        $self->render(text => '"column_names" format was not valid', status => 400);
        return;
    }
    if (scalar @{$json_parser->column_names} != scalar @{$json_parser->fields}) {
        $self->render(text => '"column_names" and "fields" are incompatible', status => 400);
        return;
    }
    delete $req_body->{column_names};
    $es_transaction->set_body(JSON::encode_json($req_body));
    $es_transaction->start;
};

sub bad_request {
    my ($self) = @_;
    my $url_path = $self->req->url->path->to_abs_string;
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
