package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';
use JSON::Streaming::Reader;
use JSON::Streaming::Writer;
use IO::Scalar;
use JSON;

sub es_query {
    my ($self) = @_;

    my $format = $self->stash('format') || 'json';
    $self->app->log->debug("format is $format");
    if (! grep {$format eq $_} qw(json csv tsv)) {
        $self->render(text => '', status => 406);
        return;
    }

    my $path_query = $self->req->url->path_query;
    my $http_method = $self->req->method;

    my $es_user_agent = Mojo::UserAgent->new();
    $es_user_agent->ioloop(Mojo::IOLoop->new);
    my ($doc_index, $doc_type, $doc_id) = map {$self->stash($_)} qw(doc_index doc_type doc_id);
    my $es_tx = $es_user_agent->build_tx($http_method => 'localhost:9200/'.$doc_index.'/'.$doc_type.'/'.$doc_id);
    $es_tx->req->headers($self->req->headers);
    $es_tx->req->body($self->req->body);
    $es_tx->res->max_message_size(0);

    $es_user_agent->on(error => sub {
        my ($es_user_agent, $error_string) = @_;
        $self->finish;
    });

    my $have_sent_headers = 0;
    $es_tx->res->content->unsubscribe('read');

    if ($format eq 'json') {
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
            #$es_user_agent->ioloop->stop;
            $self->finish;
        });
    }
    elsif ($format eq 'csv' || $format eq 'tsv') {
        my @json_properties;
        my $parsing_hit;
        my $json_buffer = '';
        my $json_buffer_handle;
        my $jsonw;
        my $lines_to_write;
        my $length_written;
        my $separator = $format eq 'csv' ? ','
                        : $format eq 'tsv' ? "\t"
                        : undef;
        my $jsonr = JSON::Streaming::Reader->event_based(
            start_object => sub {
                if (scalar @json_properties == 2 && $json_properties[1] eq 'hits') {
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
                if (scalar @json_properties == 2) {
                    $parsing_hit = 0;
                    $json_buffer_handle->close();
                    my $decoded_json = JSON::decode_json($json_buffer);
                    my $cols = process_json($decoded_json);
                    $lines_to_write .= join($separator, @$cols)."\n";
                }
            },
            start_array => sub {
                if ($parsing_hit) {
                    $jsonw->start_object;
                }
            },
            end_array => sub {
                if ($parsing_hit) {
                    $jsonw->end_object;
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
                    $jsonw->end_property;
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
                $json_buffer_handle->close();
            },
        );

        $es_tx->res->content->on(read => sub {
            my ($content, $bytes) = @_;
            $jsonr->feed_buffer(\$bytes);
            return if !$lines_to_write;
            if (!$have_sent_headers) {
                my $headers = $es_tx->res->headers->to_hash;
                delete $headers->{'Content-Length'};
                $self->res->headers->from_hash($headers);
                $self->res->headers->content_type($format eq 'csv' ? 'text/csv' : 'text/tab-separated-values');
                $have_sent_headers = 1;
            }
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
    }


    $es_user_agent->start($es_tx);

};

sub method_not_allowed {
    my ($self) = @_;
    $self->res->headers->allow('GET', 'HEAD', 'OPTIONS');
    $self->render(text => '', status => 405);
}

sub process_json {
    my ($json) = @_;
    my @cols = @{$json->{_source}}{'Name', 'BioSamples Accession'};
    return \@cols;
}

1;
