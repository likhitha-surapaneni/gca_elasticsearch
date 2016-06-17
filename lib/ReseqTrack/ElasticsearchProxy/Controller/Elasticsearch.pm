package ReseqTrack::ElasticsearchProxy::Controller::Elasticsearch;
use Mojo::Base 'Mojolicious::Controller';
use ReseqTrack::ElasticsearchProxy::Model::ChunkedTabWriter;
use ReseqTrack::ElasticsearchProxy::Model::ChunkedJsonWriter;
use ReseqTrack::ElasticsearchProxy::Model::ESTransaction;

sub es_search_router {
  my ($self) = @_;

  $self->render_later;

  Mojo::IOLoop->delay(sub {
    my ($delay) = @_;
    return $delay->pass if $self->req->is_finished;
    $self->req->on(finish => $delay->begin(0,0));
  },
  sub {
    my ($delay) = @_;

  my $req_body;
  if ($self->req->headers->content_type eq 'application/x-www-form-urlencoded') {
    if (my $json = $self->req->body_params->to_hash->{json}) {
      eval { $req_body = Mojo::JSON::decode_json($json); };
      if ($@) {
        return $self->bad_request("error parsing JSON");
      }
    }
  }
  if (!$req_body && $self->req->body) {
    eval { $req_body = Mojo::JSON::decode_json($self->req->body); };
    if ($@) {
      return $self->bad_request("error parsing JSON");
    }
  }

  # Things get confusing if size is a query parameter, so move it to body
  if (my $size = $self->req->url->query->param('size')) {
    $self->req->url->query->remove('size');
    $req_body //= {};
    $req_body->{size} = $size;
  }

  # respond to tsv / csv request
  my $format = $self->stash('format');
  if ($format && ($format eq 'tsv' || $format eq 'csv')) {
    my $es_path = $self->stash('es_path');
    $es_path =~ s{/_search/.*}{/_search};
    return $self->es_query_tab_chunked(format => $format, req_body => $req_body, es_path => $es_path);
  }

  if ($self->req->url->query->param('scroll')) {
    # allow scrolling, but keep scroll alive for no more than 1 minute
    $self->req->url->query->param(scroll => '1m');
    if ($req_body && exists $req_body->{size} && $req_body->{size} > 100) {
      # restrict hits size to 100 when using scrolling
      return $self->bad_request('scroll API has been limited to 100 hits per request');
    }
    return $self->es_query_direct(req_body => $req_body);
  }

  # use regular search for anything with hits size <100
  return $self->es_query_direct() if !$req_body;

  $req_body->{size} //= 10;

  # used chunked searching for any large request, hits size > 100
  return $self->es_query_json_chunked(req_body => $req_body) if $req_body->{size} > 100;
  return $self->es_query_json_chunked(req_body => $req_body) if $req_body->{size} < 0;

  # use regular search for anything with hits size <100
  return $self->es_query_direct(req_body => $req_body);

  })->catch(sub {
    my ($delay, $err) = @_;
    $self->server_error($err);
  })->wait;

}

sub es_query_direct {
  my ($self, %options) = @_;
  eval {
  $self->render_later;

  my $req_body = $options{req_body} || $self->req->body;
  my $es_path = $self->stash('es_path') || die "did not get es_path";

  my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
      port => $self->stash('es_port'),
      host => $self->stash('es_host'),
      method => $self->req->method,
      url_path => $es_path,
      url_params => $self->req->url->query->to_string,
  );

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

  $es_transaction->finished_callback( sub {
    my ($ua, $tx) = @_;
    if (!$tx->res->code) {
      $self->render(json => {error => 'elasticsearch connect error'}, status => 500);
    }
  });

  $req_body = ref($req_body) eq 'HASH' ? Mojo::JSON::encode_json($req_body) : $req_body;

  $es_transaction->set_body($req_body);
  $es_transaction->non_blocking_start;

  $self->render_later;
  };
  if ($@) {
    $self->server_error($@);
  }
}

sub es_query_json_chunked {
  my ($self, %options) = @_;

  my $req_body = $options{req_body} or die "this method requires a req_body";

  my $num_hits = $req_body->{size};
  $req_body->{size} = 100;

  my $json_writer = ReseqTrack::ElasticsearchProxy::Model::ChunkedJsonWriter->new(
      num_hits_req => $num_hits,
  );
  my $query_params = $self->req->url->query;

  my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
      port => $self->stash('es_port'),
      host => $self->stash('es_host'),
      method => $self->req->method,
      url_path => $self->stash('es_path'),
      url_params => $self->req->url->query->merge(scroll => '1m')->to_string,
  );
  $es_transaction->set_body(Mojo::JSON::encode_json($req_body));
  $es_transaction->set_headers($self->req->headers);

  Mojo::IOLoop->delay(
  sub {
    my ($delay) = @_;
    $es_transaction->finished_res_callback($delay->begin);
    $es_transaction->non_blocking_start;
  },
  sub {
    my ($delay) = @_;
    my $es_res = $es_transaction->transaction->res;
    if (!$es_res->code) {
      return $self->render(json => {error => 'elasticsearch connect error'}, status => 500);
    }
    elsif ($es_res->code != 200) {
      return $self->render(json => {error => $es_res->message}, status => $es_res->code);
    }
    my $es_headers = $es_transaction->transaction->res->headers->to_hash;
    delete $es_headers->{'Content-Length'};
    $self->res->headers->from_hash($es_headers);
    $self->_process_res_json_chunked($es_transaction, $json_writer, $delay);
  },
  )->catch(sub {
    my ($delay, $err) = @_;
    $self->server_error($err);
  })->wait;

  $self->render_later;
}

sub _process_res_json_chunked {
  my ($self, $es_transaction, $json_writer, $delay) = @_;


  eval {
    my $es_res = $es_transaction->transaction->res;
    if (!$es_res->code || $es_res->code !=200) {
      die $es_res->message;
    }

    my $more_json = eval {return $json_writer->process_json($es_res->json, 100)};
    if ($@) {
      die "Error processing json: $@";
    }
    if ($json_writer->is_finished) {
        $more_json //= '';
        $more_json .= $json_writer->closing_json;
        if ($delay->data('chunked')) {
          $self->write_chunk($more_json => sub {$self->finish});
        }
        else {
          $self->res->headers->content_length($json_writer->content_length);
          $self->write($more_json => sub {$self->finish});
        }
        return;
    }

    $self->res->headers->transfer_encoding('chunked');
    $delay->data(chunked => 1);

    $es_transaction->url_path('/_search/scroll');
    $es_transaction->new_transaction();
    $es_transaction->set_body($json_writer->scroll_id);

    $delay->steps( sub {
      my ($delay) = @_;
      $es_transaction->finished_res_callback($delay->begin);
      $es_transaction->non_blocking_start;
      $self->write_chunk($more_json => sub {
          $es_transaction->non_blocking_start;
      });
    },
    sub {
      my ($delay) = @_;
      $self->_process_res_json_chunked($es_transaction, $json_writer, $delay);
    });

  };
  if ($@) {
    $self->res->code(500);
    $self->app->log->error($@);
    $self->write_chunk('Truncated output: server error' => sub {$self->finish});
  }
}

sub es_query_tab_chunked {
  my ($self, %options) = @_;

  my $req_body = $options{req_body};
  my $format = $options{format} || $self->stash('format');
  my $es_path = $options{es_path} || $self->stash('es_path');

  if (! $req_body->{fields}
      || ref($req_body->{fields}) ne 'ARRAY'
      || (scalar grep {! defined $_ || ref($_)} @{$req_body->{fields}})) {
      return $self->render(text => 'request body does not give "fields"', status => 400);
  }
  my $column_names = $req_body->{column_names} // $req_body->{fields};
  if (! $column_names
        || ref($column_names) ne 'ARRAY'
        || (scalar grep {! defined $_ || ref($_)} @$column_names)
        || (scalar @$column_names != scalar @{$req_body->{fields}})) {
      return $self->render(text => '"column_names" not valid', status => 400);
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

  my $tab_writer = ReseqTrack::ElasticsearchProxy::Model::ChunkedTabWriter->new(
      column_names => $column_names,
      fields => $req_body->{fields},
      num_hits_req => $num_hits,
      format => $format
  );
  my $es_transaction = ReseqTrack::ElasticsearchProxy::Model::ESTransaction->new(
      port => $self->stash('es_port'),
      host => $self->stash('es_host'),
      method => $self->req->method,
      url_path => $es_path,
      url_params => 'scroll=1m'
  );

  $es_transaction->set_body(Mojo::JSON::encode_json($req_body));

  Mojo::IOLoop->delay(
  sub {
    my ($delay) = @_;
    $es_transaction->finished_res_callback($delay->begin);
    $es_transaction->non_blocking_start;
  },
  sub {
    my ($delay) = @_;
    if (my $error = $es_transaction->transaction->error) {
      if (!$error->{code}) {
        return $self->render(text => 'elasticsearch connect error', status => 500);
      }
      return $self->render(text => $error->{message}, status => $error->{code});
    }
    my $es_headers = $es_transaction->transaction->res->headers->to_hash;
    delete $es_headers->{'Content-Length'};
    $self->res->headers->from_hash($es_headers);
    $self->res->headers->content_type($tab_writer->format eq 'csv' ? 'text/csv' : 'text/tab-separated-values');
    $self->_process_res_tab_chunked($es_transaction, $tab_writer, $delay);
  }
  )->catch(sub {
    my ($delay, $err) = @_;
    $self->res->code(500);
    $self->write_chunk('Truncated output: server error' => sub {$self->finish});
    $self->app->log->error($@);
  })->wait;

  $self->render_later;

};

sub _process_res_tab_chunked {
  my ($self, $es_transaction, $tab_writer, $delay) = @_;

  eval {
    my $es_res = $es_transaction->transaction->res;
    if (!$es_res->code || $es_res->code !=200) {
      die $es_res->message;
    }

    my $tab_lines = eval {return $tab_writer->process_json($es_res->json, 100)};
    if ($@) {
      die "Error converting json to delimited text: $@";
    }

    if ($tab_writer->is_finished) {
      if ($delay->data('chunked')) {
        return $self->finish if !$tab_lines;
        $self->write_chunk($tab_lines => sub {
          return $self->finish;
        });
      }
      else {
        $self->res->headers->content_length($tab_writer->content_length);
        $self->write($tab_writer->header_lines . ($tab_lines // '') => sub {$self->finish});
      }
      return;
    }


    $es_transaction->url_path('/_search/scroll');
    $es_transaction->new_transaction();
    $es_transaction->set_body($tab_writer->scroll_id);

    $delay->steps( sub {
      my ($delay) = @_;
      return $delay->pass if $delay->data('chunked');
      $self->res->headers->transfer_encoding('chunked');
      $delay->data(chunked => 1);
      $self->write_chunk($tab_writer->header_lines => $delay->begin);
    },
    sub {
      my ($delay) = @_;
      $es_transaction->finished_res_callback($delay->begin);
      $self->write_chunk($tab_lines => sub {
        $es_transaction->non_blocking_start;
      });
    },
    sub {
      my ($delay) = @_;
      $self->_process_res_tab_chunked($es_transaction, $tab_writer, $delay);
    });

  };
  if ($@) {
    $self->res->code(500);
    $self->write_chunk('Truncated output: server error' => sub {$self->finish});
    $self->app->log->error($@);
  }
}

sub bad_request {
    my ($self, $text) = @_;
    $self->respond_to(
        tsv => sub {$self->render(text => $text, status => 400)},
        csv => sub {$self->render(text => $text, status => 400)},
        any => sub {$self->render(json => {error => $text}, status => 400)},
    );
}

sub server_error {
    my ($self, $err) = @_;
    $self->app->log->error($err);
    my $text = 'server error';
    $self->respond_to(
        tsv => sub {$self->render(text => $text, status => 500)},
        csv => sub {$self->render(text => $text, status => 500)},
        any => sub {$self->render(json => {error => $text}, status => 500)},
    );
}

sub forbidden {
    my ($self) = @_;
    $self->app->log->error('forbidden');
    my $text = 'endpoint not supported';
    $self->respond_to(
        tsv => sub {$self->render(text => $text, status => 403)},
        csv => sub {$self->render(text => $text, status => 403)},
        any => sub {$self->render(json => {error => $text}, status => 403)},
    );
}

sub method_not_allowed {
    my ($self) = @_;
    $self->res->headers->allow('GET', 'HEAD', 'OPTIONS');
    my $text = 'method not allowed';
    $self->respond_to(
        tsv => sub {$self->render(text => $text, status => 405)},
        csv => sub {$self->render(text => $text, status => 405)},
        any => sub {$self->render(json => {error => $text}, status => 405)},
    );
}

1;
