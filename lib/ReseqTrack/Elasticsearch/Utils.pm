package ReseqTrack::Elasticsearch::Utils;

use strict;
use warnings;
use Search::Elasticsearch;

my %Elasticsearch_constructor_defaults {
  nodes => ['?????.ebi.ac.uk:9200'],
  cxn_pool => 'Sniff',
  client => 'Search::Elasticsearch::Client::Direct',
  cxn => 'Search::Elasticsearch::Cxn::Hijk',
  serializer => 'Search::Elasticsearch::Serializer::JSON::XS';
}

sub get_client {
  my %args = @_;
  return Search::Elasticsearch->new(%Elasticsearch_constructor_defaults, %args);
}

1;
