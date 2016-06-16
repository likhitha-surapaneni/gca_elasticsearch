package ReseqTrack::ElasticsearchProxy::Model::ChunkedJsonWriter;

use namespace::autoclean;
use Moose;
use Mojo::JSON;
use v5.16;

has 'num_hits_req' => (is => 'rw', isa => 'Int');

has 'closing_json' => (is => 'rw', isa => 'Str');

has 'is_finished' => (is => 'rw', isa => 'Bool', default => 0);
has 'content_length' => (is => 'rw', isa => 'Int', default => 0);
has 'scroll_id' => (is => 'rw', isa => 'Maybe[Str]');

has '_num_hits_written' => (is => 'rw', isa => 'Int', default => 0);


sub process_json {
    my ($self, $json_obj) = @_;

    my $num_hits_written = $self->_num_hits_written;
    my $num_hits_req = $self->num_hits_req;

    $self->scroll_id($json_obj->{_scroll_id});
    delete $json_obj->{_scroll_id};

    my @hits_json;
    my $hits = $json_obj->{hits}{hits};
    my $return_string = '';

    if ($num_hits_written) {
      push(@hits_json, '');
    }
    else {
      my $breaker = '__CHUNKED_JSON_WRITER_BREAKPOINT__';
      $json_obj->{hits}{hits} = [$breaker];
      my $json_string = Mojo::JSON::encode_json($json_obj);
      my ($opening, $closing) = $json_string =~ /^(.*)"$breaker"(.*)$/;
      $return_string = $opening;
      $self->closing_json($closing);
      $self->content_length(length($closing));
    }

    my $new_hits_written = 0;
    HIT:
    foreach my $hit (@$hits) {
      push(@hits_json, Mojo::JSON::encode_json($hit));
      $new_hits_written +=1;
      if ($num_hits_req >= 0 && $num_hits_written == $num_hits_req) {
        $self->is_finished(1);
        last HIT;
      }
    };

    if (!$new_hits_written) {
      $self->is_finished(1);
    }

    $return_string .= join(',', @hits_json);

    $self->_num_hits_written($num_hits_written + $new_hits_written);

    $self->content_length($self->content_length + length($return_string));


    return $return_string;
}

__PACKAGE__->meta->make_immutable;

1;

