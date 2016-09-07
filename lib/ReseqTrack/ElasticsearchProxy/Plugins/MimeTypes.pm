package ReseqTrack::ElasticsearchProxy::Plugins::AngularJS;
use Mojo::Base qw{ Mojolicious::Plugin };

sub register {
    my ($self, $app, $args) = @_;
    my $types = $app->types;

    $types->type(doc => 'application/msword');
    $types->type(dot => 'application/msword');
    $types->type(docx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    $types->type(dotx => 'application/vnd.openxmlformats-officedocument.wordprocessingml.template');
    $types->type(docm => 'application/vnd.ms-word.document.macroEnabled.12');
    $types->type(dotm => 'application/vnd.ms-word.template.macroEnabled.12');
    $types->type(xls => 'application/vnd.ms-excel');
    $types->type(xlt => 'application/vnd.ms-excel');
    $types->type(xla => 'application/vnd.ms-excel');
    $types->type(xlsx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    $types->type(xltx => 'application/vnd.openxmlformats-officedocument.spreadsheetml.template');
    $types->type(xlsm => 'application/vnd.ms-excel.sheet.macroEnabled.12');
    $types->type(xltm => 'application/vnd.ms-excel.template.macroEnabled.12');
    $types->type(xlam => 'application/vnd.ms-excel.addin.macroEnabled.12');
    $types->type(xlsb => 'application/vnd.ms-excel.sheet.binary.macroEnabled.12');
    $types->type(ppt => 'application/vnd.ms-powerpoint');
    $types->type(pot => 'application/vnd.ms-powerpoint');
    $types->type(pps => 'application/vnd.ms-powerpoint');
    $types->type(ppa => 'application/vnd.ms-powerpoint');
    $types->type(pptx => 'application/vnd.openxmlformats-officedocument.presentationml.presentation');
    $types->type(potx => 'application/vnd.openxmlformats-officedocument.presentationml.template');
    $types->type(ppsx => 'application/vnd.openxmlformats-officedocument.presentationml.slideshow');
    $types->type(ppam => 'application/vnd.ms-powerpoint.addin.macroEnabled.12');
    $types->type(pptm => 'application/vnd.ms-powerpoint.presentation.macroEnabled.12');
    $types->type(potm => 'application/vnd.ms-powerpoint.template.macroEnabled.12');
    $types->type(ppsm => 'application/vnd.ms-powerpoint.slideshow.macroEnabled.12');
}

1;
