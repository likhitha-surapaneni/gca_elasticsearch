package ReseqTrack::ElasticsearchProxy::Plugins::Redirect;
use Mojo::Base qw{ Mojolicious::Plugin };
use Mojo::Util qw(slurp);
use Mojo::IOLoop;
use File::stat;


sub refresh_redirection_hash {
    my ($self, $file) = @_;

    if (! -f $file) {
        $self->{redirection_hash} = {};
        $self->{mtime} = undef;
        return;
    }

    my $st = stat($file) or die "could not stat $file $!";
    my $mtime = $st->mtime;

    return if ($self->{mtime} && $self->{mtime} == $mtime);
    $self->{mtime} = $mtime;

    my %redirect_to;
    my $redirections = slurp($file);
    foreach my $line (split("\n", $redirections)) {
        my ($from, $to) = split("\t", $line);
        if ($from && $to) {
            $redirect_to{$from} = $to;
        }
    }
    $self->{redirection_hash} = \%redirect_to;
}

sub register {
    my ($self, $app, $args) = @_;
    $app->plugin('DefaultHelpers');
    my $file = $args->{file};

    $self->refresh_redirection_hash($file);

    Mojo::IOLoop->recurring(
        300 => sub { $self->refresh_redirection_hash($file)}
    );

    $app->routes->add_condition('has_redirect' => sub {
        my ($route, $controller, $captures) = @_;
        if (my $redirect = $self->{redirection_hash}{Mojo::Util::url_unescape( $controller->req->url->path )}) {
            $controller->stash(redirect_to => $redirect);
            return 1;
        }
        return undef;
    });

    $app->routes->any('/*')->over('has_redirect' => 1)->to(cb => sub {
        my ($controller) = @_;
        $controller->redirect_to($controller->stash('redirect_to'));
    });
}

1;
