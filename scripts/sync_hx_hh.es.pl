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
  $es_to{$to_es_host} = Search::Elasticsearch->new(nodes => "$to_es_host:9200", client => '1_0::Direct', request_timeout => 240)
}
my $es_from = Search::Elasticsearch->new(nodes => "$from_es_host:9200", client => '1_0::Direct', request_timeout => 240);

my ($sec,$min,$hour,$day,$month,$year) = localtime();
my $datestamp = sprintf('%04d%02d%02d_%02d%02d%02d', $year+1900, $month+1, $day, $hour, $min, $sec);
my $snapshot_name = 'sync_hx_hh_'.$datestamp;

my $repo_res = $es_from->snapshot->get_repository(
    repository => $repo,
);
my $repo_dir = $repo_res->{$repo}{settings}{location} || die "did not get repo directory for $repo";
$repo_dir .= '/'; # important for rsync
$repo_dir =~ s{//}{/}g;

my %full_index_names;
foreach my $index_name (@snap_indices) {
  my $index_status = eval{return $es_from->indices->get(index => $index_name);};
  if (my $error = $@) {
    die "error getting index status for $index_name: ".$error->{text};
  }
  $full_index_names{$index_name} = [keys %$index_status];
}

eval{$es_from->snapshot->create(
    repository => $repo,
    snapshot => $snapshot_name,
    wait_for_completion => 1,
    body => {
        indices => join(',', map {@$_} values %full_index_names),
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

  RESTORE:
  foreach my $restore_index (@restore_indices) {
    next RESTORE if !$full_index_names{$restore_index}; # Do not try to restore an index if we have not synced it.
    my $get_alias_res = eval{return $es->indices->get_alias(
      index => $restore_index,
    );};
    if (my $error = $@) {
      die "error getting index alias for $restore_index: ".$error->{text};
    }
    my @existing_aliases = grep {exists $get_alias_res->{$_}->{aliases}{$restore_index}} keys %$get_alias_res;

    my @new_index_names;
    foreach my $full_index_name (@{$full_index_names{$restore_index}}) {
      my $new_index_name = sprintf('%s_%s', $restore_index, $datestamp);
      eval{$es->snapshot->restore(
        repository => $repo,
        snapshot => $snapshot_name,
        wait_for_completion => 1,
        body => {
            indices => $full_index_name,
            include_global_state => 0,
            rename_pattern => $full_index_name,
            rename_replacement => $new_index_name,
            include_aliases => 0,
        }
      );};
      if (my $error = $@) {
        die "error restoring snapshot $snapshot_name from $repo for $restore_index: ".$error->{text};
      }
      push(@new_index_names, $new_index_name);
    }

    eval{$es->indices->update_aliases(
      body => {
        actions => [
          (map { {add => {alias => $restore_index, index => $_}} } @new_index_names),
          (map { {remove => {alias => $restore_index, index => $_}} } @existing_aliases)
        ]
      }
    );};
    if (my $error = $@) {
      die "error changing alias from @existing_aliases to @new_index_names for index $restore_index: ".$error->{text};
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

=pod

=head1 NAME

gca_elasticsearch/scripts/sync_hx_hh.es.pl

=head1 SYNOPSIS

perl gca_elasticsearch/scripts/sync_hx_hh.es.pl --repo hipsci_repo --snap_index hipsci

=over

=item 1.

Takes a snapshot of your index on your staging server

=item 2.

Uses rsync to copy the snapshot to your production server

=item 3.

Restores the index on the production server with a new name

=item 4.

Changes alias names on the production server to point to the newly restored index

=back

=head1 DESCRIPTION

We have 3 running elasticsearch instances: Hinxton staging (hx), Hemel production (pg), Hinxton fallback (oy)

The production servers should be responsible for serving data only; they should not be used for building the index.
Therefore, we BUILD indices for a project on the Hinxton staging server.
Then we take a snapshot to disk in Hinxton every night so we have full backups of what had been built.
Next, we rsync the snapshot to pg/oy, and restore the index in pg/oy, so all three servers are serving the same content to users.

This script requires that indexes on the production servers uses alias names.
For example, "hipsci" should be an alias pointing to the index "hipsci_20160706"

See L</SETUP> to get your elasticsearch index set up properly.

=head1 OPTIONS

=over 12

=item -from_es_host

The name of the staging server in which you have built your index: default is ves-hx-e4

=item -to_es_host

Name of the production servers which you sync TO: defaults to ves-oy-e4, ves-pg-e4

=item -repo

Name of the repository to use for snapshotting and rsyncing.
See L<elasticsearch documentation|https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html> for details on how to set up a repository in elasticsearch

=item -snap_index

Name of any index which should be snapshotted. I suggest let each project snapshot its own indexes
e.g. -snap_index igsr -snap_index igsr_beta

=item -restore

Boolean, default 1. Tells the script to restore the index on production servers.
Type --norestore if you want to snapshot in Hinxton but without rsyncing and restoring on the production servers

=item -restore_only

Use this option if you want to snapshot multiple indexes but only restore some of them
e.g. -snap_index igsr -snap_index igsr_beta -restore -restore_only igsr

=back

=head1 SETUP

Steps to be taken before you use this script:

=over 4

=item 1. Create a new index on the staging server

The index name should not be the short friendly name, e.g. use "hipsci_build1"

curl -XPUT http://ves-hx-e3:9200/hipsci_build1

=item 2. Create a alias

L<An alias|https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html>
makes your index available under the shorter friendlier name, e.g. "hipsci"

curl -XPOST http://ves-hx-e3:9200/_aliases -d '{"actions":[{"add":{"index":"hipsci_20160706","alias:"hipsci"}}]}'

=item 3. Build the index

Update index settings, using the L<Elasticsearch documentation|https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-update-settings.html>

Load mappings to tell elasticsearch how to store each field you give it.
Use the L<Elasticsearch documentation to help you|https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-put-mapping.html>

Load your documents. Your project should have its own scripts for loading documents from the project's data to meet the project's requirements.
Use the L<Elasticsearch documentation to help you|https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html>

=item 4. Create a snapshot repo on the staging server

curl -XPUT http://ves-hx-e3:9200/_snapshot/hipsci_repo/ -d '{"type":"fs","settings":{"location":"/path/to/staging/disk"}}'

The /path/to/staging/disk should be read-write accessible to the unix user running elasticsearch (w3_vg02)

L<Elasticsearch documentation has more details|https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-snapshots.html>

=item 5. Create a snapshot repo on each production server

curl -XPUT http://ves-pg-e3:9200/_snapshot/hipsci_repo/ -d '{"type":"fs","settings":{"location":"/path/to/pg/disk","readonly":true}}'

Note that readonly can be set to true, because we only write to it by rsync. The /path/to/pg/disk should be write-accessible
to the user who runs THIS script (reseq_adm)

=back

=cut
