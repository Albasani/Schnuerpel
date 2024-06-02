#!/usr/bin/perl -sw
#
# $Id: YearMonthGroupID.pm 647 2012-01-04 03:11:52Z alba $
#
# Copyright 2011-2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
package Schnuerpel::YearMonthGroupID;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &CACHE_FILENAME
  &calc_totals
  &mkdir_if_not_exist
  &read_cache_file
  &report_all
  &report_attribute_count
  &report_group_count
  &update_cache_file
  &write_cache_file
);

use strict;
use Carp qw( confess );

# use Data::Dumper qw( Dumper );

use constant DEBUG => 1;

use constant CACHE_FILENAME => 'cache.txt';

use constant ATTRIBUTE_NAMES => ( 'bytes', 'client', 'lines', 'path' );
use constant LINE_WIDTH => 74;
use constant COL1_FMT => '%-45s';
use constant POSTS_FILENAME_FMT => '%s/posts.txt';
use constant PATHS_FILENAME_FMT => '%s/paths.txt';
use constant CLIENTS_FILENAME_FMT => '%s/clients.txt';
use constant CACHE_FILENAME_FMT => '%s/' . CACHE_FILENAME;

######################################################################
# DATA STRUCTURES
######################################################################
# $file_name ... a string
#
# $rh_id_attribute ... reference to hash
#   -> key = message id, value = reference to hash
#      -> key = attribute name, see ATTRIBUTE_NAMES
#         value = attribute value, integer or string
#
# $rh_group_totals ... reference to hash
#   -> key = 'path', value = $rh_attribute_count
#      key = 'client', value = $rh_attribute_count
#      key = 'posts', value = integer
#      key = 'bytes', value = integer
#      key = 'lines', value = integer
#
# $rh_hierarchy_totals ... reference to hash
#   -> key = 'path', value = $rh_attribute_count
#      key = 'client', value = $rh_attribute_count
#      key = 'posts', value = integer
#
# $rh_attribute_count ... reference to hash
#   -> key = string
#      value = number of occurences, integer
#
# $rh_group_count ... reference to hash
#   -> key = group name, string
#      value = $rh_group_totals
#
######################################################################

######################################################################
sub read_cache_file(@)
######################################################################
# Named Parameters:
# - file_name ... input
# - rh_id_attribute ... output
######################################################################
# Return value:
# -1 if file can't be opened
# number of read items on success
######################################################################
{
  my %param = @_;
  my $file_name = $param{'file_name'} || confess 'Undefined $param{"file_name"}';
  my $rh_id_attribute = $param{'rh_id_attribute'} || confess 'Undefined $param{"rh_id_attribute"}';

  my $file;
  if (!open($file, '<', $file_name)) { return -1; }

  {
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime,
      $mtime, $ctime, $blksize, $blocks) = stat($file_name);
    if (!defined($mtime))
    {
      confess "Can't stat file $file_name: $!";
    }
    $rh_id_attribute->{'.cache.mtime'} = $mtime;
  }

  my $result = 0;
  my $rh_attribute;
  while(my $line = <$file>)
  {
    chomp($line);
    if ($line =~ m#^\t(\w+)=(.*)$#)
    {
      my $old = $rh_attribute->{$1};
      if (defined($old) && $old ne $2)
      {
        warn sprintf("Rewriting attribute %s with %s \n", $1, $2);
      }
      $rh_attribute->{$1} = $2;
    }
    else
    {
      my ( $id, $bytes ) = split(/ /, $line);
      $rh_attribute = $rh_id_attribute->{$id} ||= {};
      if (defined($bytes)) { $rh_attribute->{'bytes'} = $bytes; }
      ++$result;
    }
  }
  close($file);
  return $result; # return number of items
}

######################################################################
sub write_cache_file(@)
######################################################################
# Named Parameters:
# - file_name ... input
# - rh_id_attribute ... input
######################################################################
# Return value:
# - number of items (keys) in $rh_id_attribute
# - dies if file can't be opened
######################################################################
{
  my %param = @_;
  my $file_name = $param{'file_name'} || confess;
  my $rh_id_attribute = $param{'rh_id_attribute'} || confess;

  my $result = 0;
  my $file;
  open($file, '>', $file_name) || die "Can't write to $file_name: $!";

  my @id = sort(keys(%$rh_id_attribute));
  for my $id(@id)
  {
    # message IDs start with '<', ignore everything else
    if ($id !~ m/^</) { next; }

    ++$result;
    my $rh_attribute = $rh_id_attribute->{$id};

    # Write the byte count in second column for compatibility with
    # the output of Schnuerpel::OnOverview::CountPosts.
    my $bytes = $rh_attribute->{'bytes'};
    if (defined($bytes))
      { printf $file "%s %d\n", $id, $bytes; }
    else
      { printf $file "%s\n", $id; }

    # The new format for extra information requires additional lines.
    for my $field( &ATTRIBUTE_NAMES() )
    {
      my $value = $rh_attribute->{$field};
      if (defined($value))
      {
	$value =~ s/[\r\n].*$//;
	printf $file "\t%s=%s\n", $field, $value;
      }
    }
  }
  close($file);

  return $result; # return number of items
}

######################################################################
sub calc_totals(@)
######################################################################
# Named Parameters:
# - rh_id_attribute ... input
# - rh_group_totals ... output
# - rh_hierarchy_totals ... output
######################################################################
{
  my %param = @_;
  my $rh_id_attribute = $param{'rh_id_attribute'} || confess 'Undefined $param{"rh_id_attribute"}';
  my $rh_group_totals = $param{'rh_group_totals'} || confess 'Undefined $param{"rh_group_totals"}';
  my $rh_hierarchy_totals = $param{'rh_hierarchy_totals'} || confess 'Undefined $param{"rh_hierarchy_totals"}';

  my $rh_hierarchy_paths = $rh_hierarchy_totals->{'path'} ||= {};
  my $rh_hierarchy_clients = $rh_hierarchy_totals->{'client'} ||= {};
  my $rh_group_paths = $rh_group_totals->{'path'} ||= {};
  my $rh_group_clients = $rh_group_totals->{'client'} ||= {};

  my $total_posts = 0;
  my $total_bytes = 0;
  my $total_lines = 0;
  while(my ($id, $rh_attribute) = each %$rh_id_attribute)
  {
    # message IDs start with '<', ignore everything else
    if ($id !~ m/^</) { next; }

    $total_posts++;
    $total_bytes += ($rh_attribute->{'bytes'} || 0);
    $total_lines += ($rh_attribute->{'lines'} || 0);

    my $path = $rh_attribute->{'path'} || '-';
    $rh_hierarchy_paths->{$path}++;
    $rh_group_paths->{$path}++;

    my $client = $rh_attribute->{'client'} || '-';
    $rh_hierarchy_clients->{$client}++;
    $rh_group_clients->{$client}++;
  }
  $rh_group_totals->{'bytes'} = $total_bytes;
  $rh_group_totals->{'lines'} = $total_lines;

  if (DEBUG && defined($rh_group_totals->{'.posts'}))
  {
    $rh_group_totals->{'.posts'} == $total_posts ||
      confess sprintf(
	'$rh_group_totals->{".posts"} = %d, $total_posts = %d',
	$rh_group_totals->{'.posts'}, $total_posts
      );
  }
  $rh_group_totals->{'.posts'} = $total_posts;
  $rh_hierarchy_totals->{'.posts'} += $total_posts;
}

######################################################################
sub update_cache_file(@)
######################################################################
# Named parameters:
# - $dir_name
# - $rh_id_attribute
# - $rh_group_totals
# - $rh_hierarchy_totals
######################################################################
{
  my %param = @_;
  my $dir_name = $param{'dir_name'} || confess;
  my $rh_id_attribute = $param{'rh_id_attribute'} || confess;
  my $rh_group_totals = $param{'rh_group_totals'} || confess;
  my $rh_hierarchy_totals = $param{'rh_hierarchy_totals'} || confess;

  my $file_name = sprintf(CACHE_FILENAME_FMT, $dir_name);

  read_cache_file(
    'file_name' => $file_name,
    'rh_id_attribute' => $rh_id_attribute
  );
  $rh_group_totals->{'.posts'} = write_cache_file(
    'file_name' => $file_name,
    'rh_id_attribute' => $rh_id_attribute
  );
  calc_totals(
    'rh_id_attribute' => $rh_id_attribute,
    'rh_group_totals' => $rh_group_totals,
    'rh_hierarchy_totals' => $rh_hierarchy_totals
  );
}

######################################################################
sub report_attribute_count(@)
######################################################################
# Named parameters:
# - $file
# - $rh_attribute_count
# - $total_count
# - $attribute_title
######################################################################
{
  my %param = @_;
  my $file = $param{'file'} || confess;

  my $rh_attribute_count = $param{'rh_attribute_count'};
  defined($rh_attribute_count) ||
    confess 'Undefined $param{"rh_attribute_count"}';

  my $total_count = $param{'total_count'};
  defined($total_count) ||
    confess 'Undefined $param{"total_count"}';

  my $attribute_title = $param{'attribute_title'} || confess;

  printf $file COL1_FMT . "%6s%9s\n%s\n",
    $attribute_title, 'Posts', '%', '-' x LINE_WIDTH;

  my @key = sort
    { $rh_attribute_count->{$b} <=> $rh_attribute_count->{$a} }
    keys(%$rh_attribute_count);

  my $verify_count = 0;
  for my $value(@key)
  {
    my $count = $rh_attribute_count->{$value};
    printf $file COL1_FMT . "%6d%9.1f\n",
      $value, $count, 100.0 * $count / $total_count;
    if (DEBUG) { $verify_count += $count; }
  }
  if (DEBUG && $verify_count != $total_count) { confess; }
  printf $file "%s\n", '-' x LINE_WIDTH;
  printf $file COL1_FMT . "%6d\n", '', $total_count;
}

######################################################################
sub report_group_count(@)
######################################################################
# Named parameters:
# - $file
# - $attribute_title
# - $rh_group_count
######################################################################
# Return value:
# - total sum of all $rh_group_count->{...}->{".posts"}
######################################################################
{
  my %param = @_;
  my $file = $param{'file'} || confess;
  my $attribute_title = $param{'attribute_title'} || 'Group';
  my $rh_group_count = $param{'rh_group_count'} || confess;

  printf $file COL1_FMT . "%6s%9s%14s\n%s\n",
    $attribute_title, 'Posts', 'Lines', 'Bytes', '-' x LINE_WIDTH;

  my $total_count = 0;
  my $total_lines = 0;
  my $total_bytes = 0;
  my @groups = sort keys %$rh_group_count;
  for my $group(@groups)
  {
    # Group names do not start with '.'
    if ($group =~ m/^\./) { next; }

    my $rh_count = $rh_group_count->{$group};

    my $count = $rh_count->{'.posts'};
    defined($count) || confess 'Undefined $rh_count->{".posts"}';
    my $lines = $rh_count->{'lines'};
    defined($lines) || confess 'Undefined $rh_count->{"lines"}';
    my $bytes = $rh_count->{'bytes'};
    defined($bytes) || confess 'Undefined $rh_count->{"bytes"}';
    printf $file COL1_FMT . "%6d%9d%14d\n",
      $group, $count, $lines, $bytes;

    $total_count += $count;
    $total_lines += $lines;
    $total_bytes += $bytes;
  }

  printf $file "%s\n", '-' x LINE_WIDTH;
  printf $file COL1_FMT . "%6d%9d%14d\n",
    '', $total_count, $total_lines, $total_bytes;

  return $total_count;
}

######################################################################
sub mkdir_if_not_exist($)
######################################################################
{
  my $dir_name = shift || confess;
  if (! -d $dir_name && !mkdir($dir_name))
  {
    die "Can't create directory $dir_name: $!";
  }
}

######################################################################
sub report_totals(@)
######################################################################
{
  my %param = @_;
  my $dir_name = $param{'dir_name'} || '.';
  my $rh_hierarchy_totals = $param{'rh_hierarchy_totals'} || confess 'Undefined $param{"rh_hierarchy_totals"}';

  ref($rh_hierarchy_totals) eq 'HASH' || confess;

  my $total_count = $rh_hierarchy_totals->{'.posts'};
  defined($total_count) || confess 'Undefined $rh_hierarchy_totals->{".posts"}';

  {
    my $file;
    my $file_name = sprintf(PATHS_FILENAME_FMT, $dir_name);
    open($file, '>', $file_name) || die "Can't open $file_name: $!";
    report_attribute_count(
      'file' => $file,
      'attribute_title' => 'Path',
      'rh_attribute_count' => $rh_hierarchy_totals->{'path'},
      'total_count' => $total_count
    );
  }
  {
    my $file;
    my $file_name = sprintf(CLIENTS_FILENAME_FMT, $dir_name);
    open($file, '>', $file_name) || die "Can't open $file_name: $!";
    report_attribute_count(
      'file' => $file,
      'attribute_title' => 'Client',
      'rh_attribute_count' => $rh_hierarchy_totals->{'client'},
      'total_count' => $total_count
    );
  }
}

######################################################################
sub report_all(@)
######################################################################
{
  my %param = @_;
  my $dir_name = $param{'dir_name'} || '.';
  my $rh_group_count = $param{'rh_group_count'} || confess;
  my $rh_hierarchy_totals = $param{'rh_hierarchy_totals'} || confess;

  my $file;
  my $file_name = sprintf(POSTS_FILENAME_FMT, $dir_name);
  open($file, '>', $file_name) || die "Can't open $file_name: $!";
  my $total_count = report_group_count(
    'file' => $file,
    'rh_group_count' => $rh_group_count
  );
  close($file);

  if (DEBUG)
  {
    ($total_count == $rh_hierarchy_totals->{'.posts'}) ||
      confess "$total_count != $rh_hierarchy_totals->{'.posts'}";
  }

  if ($total_count <= 0) { return; }

  report_totals(
    'dir_name' => $dir_name,
    'rh_hierarchy_totals' => $rh_hierarchy_totals
  );

  while(my ($group, $rh_count) = each %$rh_group_count)
  {
    # Group names do not start with '.'
    if ($group =~ m/^\./) { next; }

    my $group_dir = sprintf('%s/%s', $dir_name, $group);
    mkdir_if_not_exist($group_dir);

    report_totals(
      'dir_name' => $group_dir,
      'rh_hierarchy_totals' => $rh_count
    );
  }
  
  # print Data::Dumper::Dumper( $rh_group_count ); die;
}

######################################################################
1;
######################################################################
