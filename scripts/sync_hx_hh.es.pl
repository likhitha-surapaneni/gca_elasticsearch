#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long;
use Search::Elasticsearch;
use File::Rsync;
use DBI;

my $from_es_host = 'ves-hx-e4';
my @to_es_host;
my $repo;
my @snap_indices;
my $restore = 1;
my @restore_indices;

&GetOptions(
  'from_es_host=s' =>\$from_es_host,
  'to_es_host=s' =>\@to_es_host,
  'repo=s' =>\$repo,
  'snap_index=s' =>\@snap_indices,
  'restore_only=s' =>\@restore_indices,
  'restore!' => \$restore,
);

die 'requires --repo on command line' if !$repo;
die 'requires --snap_index on command line' if !scalar @snap_indices;

# Some defaults:
if (!scalar @to_es_host) {
  @to_es_host = ('ves-pg-e4', 'ves-oy-e4');
}

if (! scalar @restore_indices) {
  @restore_indices = @snap_indices;
}

my %es_to;
foreach my $to_es_host (@to_es_host) {
  $es_to{$to_es_host} = Search::Elasticsearch->new(nodes => "$to_es_host:9200", client => '1_0::Direct', request_timeout => 120)
}
my $es_from = Search::Elasticsearch->new(nodes => "$from_es_host:9200", client => '1_0::Direct', request_timeout => 120);

my ($sec,$min,$hour,$day,$month,$year) = localtime();
my $datestamp = sprintf('%04d%02d%02d_%02d%02d%02d', $year+1900, $month+1, $day, $hour, $min, $sec);
my $snapshot_name = 'sync_hx_hh_'.$datestamp;

my $repo_res = $es_from->snapshot->get_repository(
    repository => $repo,
);
my $repo_dir = $repo_res->{$repo}{settings}{location} || die "did not get repo directory for $repo";
$repo_dir .= '/'; # important for rsync
$repo_dir =~ s{//}{/}g;

eval{$es_from->snapshot->create(
    repository => $repo,
    snapshot => $snapshot_name,
    wait_for_completion => 1,
    body => {
        indices => join(',', @snap_indices),
        include_global_state => 0,
    }
);};
if (my $error = $@) {
  die "error creating snapshot $snapshot_name in $repo for indices @snap_indices: ".$error->{text};
}

my $rsync = File::Rsync->new({archive=>1});

ES_TO:
while( my ($to_es_host, $es) = each %es_to) {
  my $to_repo_res = $es->snapshot->get_repository(
      repository => $repo,
  );
  my $to_repo_dir = $to_repo_res->{$repo}{settings}{location} || die "did not get repo directory for $repo";
  $to_repo_dir .= '/'; # important for rsync
  $to_repo_dir =~ s{//}{/}g;

  $rsync->exec({archive => 1, src => $repo_dir, dest => "$to_es_host:$to_repo_dir"})
      or die join("\n", "error syncing $repo_dir to $to_es_host:$to_repo_dir", $rsync->err);

  next ES_TO if !$restore;

  foreach my $restore_index (@restore_indices) {
    my $get_alias_res = eval{return $es->indices->get_alias(
      index => $restore_index,
    );};
    if (my $error = $@) {
      die "error getting index alias for $restore_index: ".$error->{text};
    }
    my @existing_aliases = grep {exists $get_alias_res->{$_}->{aliases}{$restore_index}} keys %$get_alias_res;

    my $new_index_name = sprintf('%s_%s', $restore_index, $datestamp);
    eval{$es->snapshot->restore(
      repository => $repo,
      snapshot => $snapshot_name,
      wait_for_completion => 1,
      body => {
          indices => $restore_index,
          include_global_state => 0,
          rename_pattern => $restore_index,
          rename_replacement => $new_index_name,
      }
    );};
    if (my $error = $@) {
      die "error restoring snapshot $snapshot_name from $repo for $restore_index: ".$error->{text};
    }

    eval{$es->indices->update_aliases(
      body => {
        actions => [
          {add => {alias => $restore_index, index => $new_index_name}},
          map { {remove => {alias => $restore_index, index => $_}} } @existing_aliases
        ]
      }
    );};
    if (my $error = $@) {
      die "error changing alias from @existing_aliases to $new_index_name for index $restore_index: ".$error->{text};
    }

    if (@existing_aliases) {
      eval{$es->indices->delete(
        index => join(',', @existing_aliases),
      );};
      if (my $error = $@) {
        die "error deleting old index @existing_aliases: ".$error->{text};
      }
    }

  }

}
