#!/usr/bin/env perl

use strict;
use warnings;

use HTTP::Daemon;
use LWP::UserAgent;
use LWP::Simple;
use List::Util qw(none);

my $daemon = HTTP::Daemon->new(LocalAddr => 'localhost', LocalPort => 8200) or die $!;
print "Please contact me at: <URL:", $daemon->url, ">\n";
my $elastic_search_server = 'localhost:9200';
my $elastic_search = LWP::UserAgent->new();

while (my $connection = $daemon->accept) {
  REQUEST:
  while (my $request = $connection->get_request(1)) {
    if ( List::Util::none {$request->method eq $_} qw(GET HEAD OPTIONS TRACE)) {
      $connection->send_error(RC_METHOD_NOT_ALLOWED);
      next REQUEST;
    }

    my $uri = $request->uri;
    $uri->host_port($elastic_search_server);
    $uri->scheme('http');

    my $es_request = HTTP::Request->new($request->method, $uri, $request->headers);
    if ($request->headers->{'Content-Length'}) {
        $es_request->content(sub {return $connection->read_buffer});
    }

    my $is_header_sent = 0;
    my $es_response = $elastic_search->request($es_request, sub {
            my ($data, $response, $protcol) = @_;
            if (!$is_header_sent) {
                $connection->send_status_line($response->status_line);
                $connection->send_header('Content-Type', $response->header('content-type'), 'Content-Length', $response->header('content-length'));
                $connection->send_crlf;
                $is_header_sent = 1;
            }
            $connection->send($data);
      });

  }
  $connection->close();
}
