#!/usr/bin/env perl

use strict;
use warnings;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::Simple;
use List::Util qw();

my $daemon = HTTP::Daemon->new(LocalAddr => '????', LocalPort => 9300);
my $elastic_search_server = '????:9300';
my $elastic_search = LWP::UserAgent->new();

while (my $connection = $daemon->accept) {
  REQUEST:
  while (my $request = $connection->get_request(1)) {
    if (! List::Util::any {$request->method eq $_} qw(GET HEAD OPTIONS TRACE)) {
      $connection->send_error(RC_METHOD_NOT_ALLOWED);
      next REQUEST;
    }

    my $uri = $request->uri;
    $uri->host_port($elastic_search_server);

    my $es_request = HTTP::Request->new($request->method, $uri, $request->header);
    $es_request->content(sub {return $connection->read_buffer});

    my $es_response = $elastic_search->request($es_request, sub {
            my ($data, $response, $protcol) = @_;
            $connection->send($data);
      });
    $daemon->send_header($es_response->headers);
    $es_response->content;

  }
  $connection->close();
}
