package ReseqTrack::ElasticsearchProxy;
use Mojo::Base 'Mojolicious';

sub startup {
    my ($self) = @_;

    $self->routes->get('/:doc_index/:doc_type/:doc_id')->to(controller=>'elasticsearch', action=>'es_query', doc_index => '', doc_type => '', doc_id => '');
    $self->routes->options('/:doc_index/:doc_type/:doc_id')->to(controller=>'elasticsearch', action=>'es_query', doc_index => '', doc_type => '', doc_id => '');

    #$self->routes->get('/*')->to(controller=>'elasticsearch', action=>'es_query');
    #$self->routes->options('/*')->to(controller=>'elasticsearch', action=>'es_query');
    $self->routes->any('/*')->to(controller=>'elasticsearch', action=>'method_not_allowed');

}

1;
