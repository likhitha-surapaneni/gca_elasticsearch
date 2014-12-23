package ReseqTrack::Elasticsearch::Adaptor;

use strict;
use warnings;
use Search::Elasticsearch;
use namespace::autoclean;
use Moose;

has client => (
  is => 'ro',
  isa => Search::Elasticsearch::Client::Direct,
  builder => '_build_client',
  lazy => 1,
)

sub _build_client {
  my ($self) = @_;
  return Search::Elasticsearch->new(
    client => 'Direct',
  );
}
