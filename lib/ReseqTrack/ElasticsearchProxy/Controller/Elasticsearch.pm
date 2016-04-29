package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';
use ReseqTrack::ElasticsearchProxy::Model::JsonToTab;
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
        if (scalar @es_path_parts < 4 || scalar @es_path_parts >5 || $es_path_parts[3] !~ /^_search(\.\w*)?$/) {
            return $self->method_not_allowed();
        }
        $es_path = join('/', @es_path_parts[0..3]);
    }
    if ($es_path eq '/test') {
        return $self->simple('/_plugin/testpage/');
    }

    $self->respond_to(
        tsv => sub {$self->es_query_tab($es_path, 'tsv')},
        csv => sub {$self->es_query_tab($es_path, 'csv')},
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
        url_params => $self->req->url->query->to_string,
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
        $es_transaction->non_blocking_start;
    }
    else {
        $self->req->on(finish => sub {
            $es_transaction->set_body($self->req->body);
            $es_transaction->non_blocking_start;
        });
    }
}

sub es_query_tab {
    my ($self, $es_path, $format) = @_;

    my $req_body;
    if ($self->req->headers->content_type eq 'application/x-www-form-urlencoded') {
        if (my $json = $self->req->body_params->to_hash->{json}) {
            eval { $req_body = JSON::decode_json($json); };
            if ($@) {
                $self->render(text => 'error encoutered while parsing JSON', status => 400);
                return;
            }
        }
    }
    if (!$req_body) {
        eval { $req_body = JSON::decode_json($self->req->body); };
        if ($@) {
            $self->render(text => 'error encoutered while parsing JSON', status => 400);
            return;
        }
    }
    if (! $req_body->{fields} || ref($req_body->{fields}) ne 'ARRAY') {
        $self->render(text => 'request body does not give "fields"', status => 400);
        return;
    }
    my $column_names = $req_body->{column_names} // $req_body->{fields};
    if (! $column_names || ref($column_names) ne 'ARRAY' || scalar @$column_names != scalar @{$req_body->{fields}}) {
        $self->render(text => '"column_names" not valid', status => 400);
        return;
    }

    my $num_hits = $req_body->{size};
    delete @{$req_body}{qw(column_names aggregations size from)};
    if (! defined $num_hits || ! exists $req_body->{sort}) {
        $req_body->{sort} = ["_doc"];
    }
    $req_body->{size} = ! defined $num_hits ? 100
                        : $num_hits < 0 ? 100
                        : $num_hits < 100 ? $num_hits
                        : 100;

    my $tab_writer = ReseqTrack::ElasticsearchProxy::Model::JsonToTab->new(
        column_names => $column_names,
        fields => $req_body->{fields},
        num_hits_req => $num_hits,
        format => $format
    );
    my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
        port => $self->app->config('elasticsearch_port'),
        host => $self->app->config('elasticsearch_host'),
        method => $self->req->method,
        url_path => $es_path,
        url_params => 'scroll=1m'
    );
    my $header_lines = $tab_writer->header_lines;



    $es_transaction->headers_callback(sub {\&first_headers_callback});
    $es_transaction->headers_callback(sub {$self->_first_headers_callback(@_, $tab_writer)});
    $es_transaction->finished_callback(sub {$self->_finished_callback($es_transaction, $tab_writer)});
    $es_transaction->errors_callback(sub {$self->finish});

    $es_transaction->set_body(JSON::encode_json($req_body));
    $es_transaction->non_blocking_start;
};

sub _first_headers_callback {
    my ($self, $es_headers, $es_code, $tab_writer) = @_;
    #$self->app->log->debug('First headers');
#use Data::Dumper; $self->app->log->debug(Data::Dumper->new([$es_headers])->Dump);
    if ($es_code !=200) {
        $self->render('', $es_code);
        return $self->finish;
    }
    delete $es_headers->{'Content-Length'};
    $self->res->headers->from_hash($es_headers);
    $self->res->headers->content_type($tab_writer->format eq 'csv' ? 'text/csv' : 'text/tab-separated-values');
    $self->res->code($es_code);
    
    $self->write($tab_writer->header_lines => sub {return;});
}

sub _finished_callback {
    my ($self, $es_transaction, $tab_writer) = @_;
    my $es_res = $es_transaction->transaction->res;
    if ($es_res->code !=200) {
        $self->write(sprintf('error getting search hits: %s', $es_res->message) => sub {$self->finish;});
        $self->res->code(400);
        return;
    }

    my $tab_lines = eval {return $tab_writer->process_json($es_res->body)};
    if ($@) {
        $self->write('Error converting json to delimited text' => sub {$self->finish;});
        $self->res->code(400);
        return;
    }

    if ($tab_writer->is_finished) {
        $self->res->headers->content_length($tab_writer->content_length);
        $self->write($tab_lines => sub {return $self->finish;});
        return;
    }

    $es_transaction->url_path('/_search/scroll');
    $es_transaction->new_transaction();
    $es_transaction->finished_callback(sub {$self->_finished_callback($es_transaction, $tab_writer)});
    $es_transaction->errors_callback(sub {$self->finish});

    $es_transaction->set_body($tab_writer->scroll_id);

    $self->write($tab_lines => sub {
        $es_transaction->non_blocking_start;
    });
    $es_transaction->pause;

}

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
