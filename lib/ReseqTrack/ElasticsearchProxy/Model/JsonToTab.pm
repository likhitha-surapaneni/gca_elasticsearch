package ReseqTrack::ElasticsearchProxy::Model::JsonToTab;

use namespace::autoclean;
use Moose;
use JSON;
use v5.16;

has 'column_names' => (is => 'rw', isa => 'ArrayRef[Str]');
has 'fields' => (is => 'rw', isa => 'ArrayRef[Str]');
has 'num_hits_req' => (is => 'rw', isa => 'Maybe[Int]');
has 'format' => (is => 'rw', isa => 'Str');

has 'is_finished' => (is => 'rw', isa => 'Bool', default => 0);
has 'content_length' => (is => 'rw', isa => 'Int', default => 0);
has 'scroll_id' => (is => 'rw', isa => 'Maybe[Str]');
has 'header_lines' => (is => 'rw', isa => 'Str');

has '_num_hits_written' => (is => 'rw', isa => 'Int', default => 0);

sub BUILD {
    my ($self) = @_;
    my $sep = fc($self->format) eq fc('csv') ? ',' : "\t";
    my $header_lines = join($sep, @{$self->column_names}) ."\n";
    $self->content_length(length($header_lines));
    $self->header_lines($header_lines);
}


sub process_json {
    my ($self, $json_string) = @_;
    my $json_obj = JSON::decode_json($json_string);

    my $sep = fc($self->format) eq fc('csv') ? ',' : "\t";
    my $sub_separator = fc($self->format) eq 'csv' ? ';' : ",";

    my $num_hits_written = $self->_num_hits_written;
    my $num_hits_req = $self->num_hits_req;

    my $return_string = '';
    HIT:
    foreach my $hit (@{$json_obj->{hits}{hits}}) {

        $return_string .= join($sep, map {
          my $field_name = $_; $hit->{fields}{$field_name} ? join($sub_separator, @{$hit->{fields}{$field_name}}) : '';
        } @{$self->fields});
        $return_string .= "\n";
        $num_hits_written +=1;
        if (defined $num_hits_req && $num_hits >= 0 && $num_hits_written == $num_hits_req) {
          $self->is_finished(1);
          last HIT;
        }
    }

    if (! scalar @{$json_obj->{hits}{hits}}) {
        $self->is_finished(1);
    }

    $self->_num_hits_written($num_hits_written);
    $self->content_length($self->content_length + length($return_string));

    $self->scroll_id($json_obj->{_scroll_id});

    return $return_string;
}

__PACKAGE__->meta->make_immutable;

1;

