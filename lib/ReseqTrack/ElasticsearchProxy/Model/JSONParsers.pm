package ReseqTrack::ElasticsearchProxy::Model::JSONParsers;
use JSON::Streaming::Reader;
use JSON::Streaming::Writer;
use IO::Scalar;
use JSON;

use namespace::autoclean;
use Moose;

has 'column_names' => (is => 'rw', isa => 'ArrayRef[Str]');
has 'fields' => (is => 'rw', isa => 'ArrayRef[Str]');
has 'reader' => (is => 'rw', isa => 'JSON::Streaming::Reader');
has 'format' => (is => 'rw', isa => 'Str');

has 'has_lines_to_write' => (is => 'rw', isa => 'Bool', default => 0);
has 'bytes_produced' => (is => 'rw', isa => 'Int', default => 0);
has '_lines_to_write' => ( is => 'rw', isa => 'ScalarRef',
    default => sub { my $empty_string = ''; return \$empty_string },
);

sub give_lines_to_write{
    my ($self) = @_;
    my $lines_to_write_ref = $self->_lines_to_write;
    my $empty_string = '';
    $self->_lines_to_write(\$empty_string);
    $self->has_lines_to_write(0);
    {
        use bytes;
        $self->bytes_produced($self->bytes_produced + length($$lines_to_write_ref));
    }
    return $lines_to_write_ref;
};

sub BUILD {
    my ($self) = @_;

    my $is_parsing_hit = 0;
    my $json_buffer = '';
    my $json_buffer_handle;
    my @properties_stack;
    my $json_writer;
    my $separator = ($self->format eq 'csv' ? ',' : "\t");
    my $newline = "\n";

    my %jsonr_callbacks;
    foreach my $event (qw(end_object start_array end_array add_string add_number add_boolean add_null)) {
        $jsonr_callbacks{$event} = sub {
            my (@args) = @_;
            if ($is_parsing_hit) {
                $json_writer->$event(@args);
            }
        };
    }
    $self->reader(JSON::Streaming::Reader->event_based(
        start_object => sub {
            if (scalar @properties_stack == 0) {
                ${$self->_lines_to_write} = join($separator, @{$self->column_names}).$newline;
                $self->has_lines_to_write(1);
            }
            elsif (scalar @properties_stack == 3 && $properties_stack[2] eq 'fields') {
                $is_parsing_hit = 1;
                $json_buffer = '';
                $json_buffer_handle = IO::Scalar->new(\$json_buffer);
                $json_writer = JSON::Streaming::Writer->for_stream($json_buffer_handle);
            }
            if ($is_parsing_hit) {
                $json_writer->start_object;
            }
        },
        start_property => sub {
            my ($property_name) = @_;
            push(@properties_stack, $property_name);
            if ($is_parsing_hit) {
                $json_writer->start_property($property_name);
            }
        },
        end_property => sub {
            pop(@properties_stack);
            if ($is_parsing_hit) {
                if (scalar @properties_stack == 2) {
                    $is_parsing_hit = 0;
                    $json_buffer_handle->close();
                    my $decoded_json = JSON::decode_json($json_buffer);
                    my @field_values;
                    foreach my $field (@{$self->fields}) {
                        if (my $field_array = $decoded_json->{$field}) {
                            push(@field_values, $field_array->[0]);
                        }
                        else {
                            push(@field_values, '');
                        }
                    }
                    ${$self->_lines_to_write} .= join($separator, @field_values).$newline;
                    $self->has_lines_to_write(1);
                }
                else {
                    $json_writer->end_property;
                }
            }
        },
        eof => sub {
            if ($is_parsing_hit) {
                $json_buffer_handle->close();
            }
        },
        %jsonr_callbacks,
    ));

};

1;
