package ReseqTrack::ElasticsearchProxy::Model::ESTransaction;

use namespace::autoclean;
use Moose;

use Mojo::UserAgent;
use Mojo::IOLoop;

has 'format' => (is => 'rw', isa => 'Str');
has 'port' => (is => 'rw', isa => 'Int');
has 'host' => (is => 'rw', isa => 'Str');
has 'method' => (is => 'rw', isa => 'Str');
has 'request_url' => (is => 'rw', isa => 'Mojo::URL');
has 'user_agent' => (is => 'ro', isa => 'Mojo::UserAgent',
    default => sub { return Mojo::UserAgent->new()->ioloop(Mojo::IOLoop->new); }
);
has 'transaction' => (is => 'rw', isa => 'Mojo::Transaction');

sub BUILD {
    my ($self) = @_;
    my $es_url = $self->request_url->clone;
    my $url_path = $es_url->path;
    my $format = $self->format;
    $url_path =~ s/\.$format$//;
    $es_url->path($url_path);
    $es_url->scheme('http');
    $es_url->host($self->host);
    $es_url->port($self->port);

    my $es_tx = $self->user_agent->build_tx($self->method => $es_url->to_string);
    $es_tx->res->max_message_size(0);
    $es_tx->res->content->unsubscribe('read');
    $self->transaction($es_tx);
};

sub set_headers {
    my ($self, $headers) = @_;
    $self->transaction->req->headers($headers);
    return $self;
};

sub set_body {
    my ($self, $body) = @_;
    $self->transaction->req->body($body);
};

sub start {
    my ($self) = @_;
    $self->user_agent->start($self->transaction);
};

sub pause {
    my ($self) = @_;
    $self->user_agent->ioloop->stop;
};
sub resume {
    my ($self) = @_;
    $self->user_agent->ioloop->start;
};

sub errors_callback {
    my ($self, $callback) = @_;
    $self->user_agent->on(error => sub {
        my ($es_user_agent, $error_string) = @_;
        &{$callback}($error_string);
    });
};

sub headers_callback {
    my ($self, $callback) = @_;
    $self->transaction->res->content->on(body => sub {
        &{$callback}($self->transaction->res->headers->to_hash, $self->transaction->res->code);
    });
};

sub partial_content_callback {
    my ($self, $callback) = @_;
    $self->transaction->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        &{$callback}($bytes);
    });
};
sub finished_callback {
    my ($self, $callback) = @_;
    $self->transaction->on(finish => $callback);
};

1;
