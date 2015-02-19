package ReseqTrack::ElasticsearchProxy::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';
use JSON::Streaming::Reader;
use JSON::Streaming::Writer;
use IO::Scalar;
use JSON;

sub register {
    my ($self, $app) = @_;

    $app->helper('es_proxy_helpers.build_es_transaction' => sub {
        my ($c, @args) = @_;
        my $es_user_agent = Mojo::UserAgent->new();
        $es_user_agent->ioloop(Mojo::IOLoop->new);

        my $es_url = $c->req->url->clone;
        if (my $format = $c->stash('format')) {
            my $url_path = $es_url->path;
            $url_path =~ s/\.$format$//;
            $es_url->path($url_path);
        }
        $es_url->scheme('http');
        $es_url->host($c->app->config('elasticsearch_host'));
        $es_url->port($c->app->config('elasticsearch_port'));
        my $http_method = $c->req->method;
        my $es_tx = $es_user_agent->build_tx($http_method => $es_url->to_string);
        $es_tx->req->headers($c->req->headers);
        $es_tx->res->max_message_size(0);

        $es_user_agent->on(error => sub {
            my ($es_user_agent, $error_string) = @_;
            $c->finish;
        });

        $es_tx->res->content->unsubscribe('read');

        $c->stash({es_tx => $es_tx, es_user_agent=> $es_user_agent});
    });

    $app->helper('es_proxy_helpers.setup_json_parsers' => sub {
        my ($c, $format, @args) = @_;
        my $is_parsing_hit = 0;
        my $json_buffer = '';
        my $json_buffer_handle;
        my @properties_stack;
        my $json_writer;
        my $separator = ($format eq 'csv' ? ',' : "\t");
        my $newline = "\n";
        my %cache_params = (
            lines_to_write => '',
            column_names => undef,
            fields => undef,
        );
        $cache_params{reader} = JSON::Streaming::Reader->event_based(
            start_object => sub {
                if (scalar @properties_stack == 0) {
                    $cache_params{lines_to_write} = join($separator, @{$cache_params{column_names}}).$newline;
                }
                elsif (scalar @properties_stack == 3 && $properties_stack[2] eq 'fields') {
                    $is_parsing_hit = 1;
                    $json_buffer = '';
                    $json_buffer_handle = IO::Scalar->new(\$json_buffer);
                    $json_writer = JSON::Streaming::Writer->for_stream($json_buffer_handle);
                }
                if ($is_parsing_hit) {
                    $json_writer->start_object;
                }
            },
            end_object => sub {
                if ($is_parsing_hit) {
                    $json_writer->end_object;
                }
            },
            start_array => sub {
                if ($is_parsing_hit) {
                    $json_writer->start_array;
                }
            },
            end_array => sub {
                if ($is_parsing_hit) {
                    $json_writer->end_array;
                }
            },
            start_property => sub {
                my ($property_name) = @_;
                push(@properties_stack, $property_name);
                if ($is_parsing_hit) {
                    $json_writer->start_property($property_name);
                }
            },
            end_property => sub {
                pop(@properties_stack);
                if ($is_parsing_hit) {
                    if (scalar @properties_stack == 2) {
                        $is_parsing_hit = 0;
                        $json_buffer_handle->close();
                        my $decoded_json = JSON::decode_json($json_buffer);
                        my @field_values;
                        foreach my $field (@{$cache_params{'fields'}}) {
                            if (my $field_array = $decoded_json->{$field}) {
                                push(@field_values, $field_array->[0]);
                            }
                            else {
                                push(@field_values, '');
                            }
                        }
                        $cache_params{lines_to_write} .= join($separator, @field_values).$newline;
                    }
                    else {
                        $json_writer->end_property;
                    }
                }
            },
            add_string => sub {
                my ($value) = @_;
                if ($is_parsing_hit) {
                    $json_writer->add_string($value);
                }
            },
            add_number => sub {
                my ($value) = @_;
                if ($is_parsing_hit) {
                    $json_writer->add_number($value);
                }
            },
            add_boolean => sub {
                my ($value) = @_;
                if ($is_parsing_hit) {
                    $json_writer->add_boolean($value);
                }
            },
            add_null => sub {
                if ($is_parsing_hit) {
                    $json_writer->add_null;
                }
            },
            eof => sub {
                if ($is_parsing_hit) {
                    $json_buffer_handle->close();
                }
            },
        );
        $c->cache->{json_parser_params} = \%cache_params;
        
    });

    $app->helper('es_proxy_helpers.process_csv_request' => sub {
        my ($c, @args) = @_;
        my $json_parser_params = $c->cache->{'json_parser_params'};
        my $es_tx = $c->stash('es_tx');
        my $es_user_agent = $c->stash('es_user_agent');
        my $req_body = JSON::decode_json($c->req->body);
        $json_parser_params->{fields} = $req_body->{fields};
        $json_parser_params->{column_names} = $req_body->{column_names} // $req_body->{fields};
        delete $req_body->{column_names};
        $es_tx->req->body(JSON::encode_json($req_body));
        $es_user_agent->start($es_tx);
    });
};

1;
