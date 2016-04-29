package ReseqTrack::ElasticsearchProxy::Model::ESTransaction;

use namespace::autoclean;
use Moose;

use Mojo::UserAgent;
use Mojo::IOLoop;

has 'port' => (is => 'rw', isa => 'Int');
has 'host' => (is => 'rw', isa => 'Str');
has 'method' => (is => 'rw', isa => 'Str');
has 'url_path' => (is => 'rw', isa => 'Str');
has 'url_params' => (is => 'rw', isa => 'Str');
has 'user_agent' => (is => 'ro', isa => 'Mojo::UserAgent',
    default => sub { return Mojo::UserAgent->new()->ioloop(Mojo::IOLoop->new); }
);
has 'transaction' => (is => 'rw', isa => 'Mojo::Transaction');

sub BUILD {
    my ($self) = @_;
    $self->new_transaction();
};

sub new_transaction {
    my ($self) = @_;
    my $es_url = sprintf('http://%s:%s/%s', $self->host, $self->port, $self->url_path);
    if (my $params = $self->url_params) {
        $es_url .= sprintf('?%s', $params);
    }
    my $es_tx = $self->user_agent->build_tx($self->method => $es_url);
    $self->transaction($es_tx);
}

sub set_headers {
    my ($self, $headers) = @_;
    $self->transaction->req->headers($headers);
    return $self;
};

sub set_body {
    my ($self, $body) = @_;
    $self->transaction->req->body($body);
};

sub non_blocking_start {
    my ($self) = @_;
    $self->user_agent->start($self->transaction => sub {return;});
    $self->user_agent->ioloop->start;
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
    $self->transaction->res->max_message_size(0);
    $self->transaction->res->content->unsubscribe('read');
    $self->transaction->res->content->on(read => sub {
        my ($content, $bytes) = @_;
        &{$callback}($bytes);
    });
};
sub finished_callback {
    my ($self, $callback) = @_;
    $self->transaction->on(finish => $callback);
};

__PACKAGE__->meta->make_immutable;

1;
