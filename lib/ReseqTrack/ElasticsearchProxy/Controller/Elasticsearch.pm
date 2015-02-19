package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';
use JSON::Streaming::Reader;
use JSON::Streaming::Writer;
use IO::Scalar;
use JSON;

sub es_query {
    my ($self) = @_;

    my $format = $self->stash('format') || $self->app->config('default_format');

    $self->app->log->debug("format is $format");
    if (! grep {$format eq $_} qw(json csv tsv)) {
        $self->render(text => '', status => 406);
        return;
    }

    my $url_query = $self->req->url->query;
    my $url_path = $self->req->url->path;
    $url_path =~ s/\.$format$//;
    my $http_method = $self->req->method;

    my $es_user_agent = Mojo::UserAgent->new();
    $es_user_agent->ioloop(Mojo::IOLoop->new);
    my $es_tx = $es_user_agent->build_tx($http_method => 'localhost:9200'.$url_path.'?'.$url_query);
    $es_tx->req->headers($self->req->headers);
    $es_tx->res->max_message_size(0);
    $self->stash({es_tx => $es_tx, es_user_agent=> $es_user_agent});

    $es_user_agent->on(error => sub {
        my ($es_user_agent, $error_string) = @_;
        $self->finish;
    });

    $es_tx->res->content->unsubscribe('read');

    if ($format eq 'json') {
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
    elsif ($format eq 'csv' || $format eq 'tsv') {
        my @json_properties;
        my $parsing_hit;
        my $json_buffer = '';
        my $json_buffer_handle;
        my $jsonw;
        my $lines_to_write = '';
        my $length_written;
        my $separator = $format eq 'csv' ? ','
                        : $format eq 'tsv' ? "\t"
                        : undef;
        my $newline = "\n";

        my $jsonr = JSON::Streaming::Reader->event_based(
            start_object => sub {
                if (scalar @json_properties == 0) {
                    $lines_to_write = join($separator, @{$self->stash('column_names')}).$newline;
                }
                elsif (scalar @json_properties == 3 && $json_properties[2] eq 'fields') {
                    $parsing_hit = 1;
                    $json_buffer = '';
                    $json_buffer_handle = IO::Scalar->new(\$json_buffer);
                    $jsonw = JSON::Streaming::Writer->for_stream($json_buffer_handle);
                }
                if ($parsing_hit) {
                    $jsonw->start_object;
                }
            },
            end_object => sub {
                if ($parsing_hit) {
                    $jsonw->end_object;
                }
            },
            start_array => sub {
                if ($parsing_hit) {
                    $jsonw->start_array;
                }
            },
            end_array => sub {
                if ($parsing_hit) {
                    $jsonw->end_array;
                }
            },
            start_property => sub {
                my ($property_name) = @_;
                push(@json_properties, $property_name);
                if ($parsing_hit) {
                    $jsonw->start_property($property_name);
                }
            },
            end_property => sub {
                pop(@json_properties);
                if ($parsing_hit) {
                    if (scalar @json_properties == 2) {
                        $parsing_hit = 0;
                        $json_buffer_handle->close();
                        my $decoded_json = JSON::decode_json($json_buffer);
                        my @field_values;
                        foreach my $field (@{$self->stash('fields')}) {
                            if (my $field_array = $decoded_json->{$field}) {
                                push(@field_values, $field_array->[0]);
                            }
                            else {
                                push(@field_values, '');
                            }
                        }
                        $lines_to_write .= join($separator, @field_values).$newline;
                    }
                    else {
                        $jsonw->end_property;
                    }
                }
            },
            add_string => sub {
                my ($value) = @_;
                if ($parsing_hit) {
                    $jsonw->add_string($value);
                }
            },
            add_number => sub {
                my ($value) = @_;
                if ($parsing_hit) {
                    $jsonw->add_number($value);
                }
            },
            add_boolean => sub {
                my ($value) = @_;
                if ($parsing_hit) {
                    $jsonw->add_boolean($value);
                }
            },
            add_null => sub {
                if ($parsing_hit) {
                    $jsonw->add_null;
                }
            },
            eof => sub {
                if ($parsing_hit) {
                    $json_buffer_handle->close();
                }
            },
        );

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
            $jsonr->feed_buffer(\$bytes);
            return if !$lines_to_write;
            {
                use bytes;
                $length_written += length($lines_to_write);
            }
            $self->write($lines_to_write => sub {$es_user_agent->ioloop->start});
            $lines_to_write = '';
            $es_user_agent->ioloop->stop;
        });

        $es_tx->on(finish => sub {
            my ($es_tx) = @_;
            $jsonr->signal_eof;
            {
                use bytes;
                $length_written += length($lines_to_write);
            }
            $self->write($lines_to_write);
            $self->res->headers->content_length($length_written);
            $self->finish;
        });

        sub process_csv_request {
            my ($self) = @_;
            my $req_body = JSON::decode_json($self->req->body);
            $self->stash({
                    fields => $req_body->{fields},
                    column_names => $req_body->{column_names} // $req_body->{fields},
                });
            delete $req_body->{column_names};
            $self->stash('es_tx')->req->body(JSON::encode_json($req_body));
            $self->stash('es_user_agent')->start($es_tx);
        }

        if ($self->req->is_finished) {
            process_csv_request($self);
        }
        else {
            $self->req->on(finish => sub {process_csv_request($self)});
        }

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
