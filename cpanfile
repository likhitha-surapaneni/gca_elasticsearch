requires 'Mojolicious';
requires 'Mojolicious::Plugin::CORS';
requires 'Mojolicious::Plugin::Directory';
requires 'JSON';
requires 'JSON::Streaming::Reader';
requires 'JSON::Streaming::Writer';
requires 'Moose';
requires 'namespace::autoclean';

on 'build' => sub {
    requires 'Module::Build::Pluggable';
    requires 'Module::Build::Pluggable::CPANfile';
};
