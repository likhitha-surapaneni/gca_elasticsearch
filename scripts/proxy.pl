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
my $read_size = 1000000;

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

    my $request_bytes_read = 0;
    my $request_content_length = $request->content_length;
    my $es_request = HTTP::Request->new($request->method, $uri, $request->headers);
    $es_request->content(sub {
        if ($request_bytes_read >= $request_content_length) {
            return '';
        }
        if (my $read_buffer = $connection->read_buffer('')) {
            $request_bytes_read += length($read_buffer);
            return $read_buffer;
        }
        else {
            my $received;
            $connection->recv($received, $read_size);
            $request_bytes_read += length($read_buffer);
            return $received;
        }
    });

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
      }, $read_size);

  }
  $connection->close();
}
