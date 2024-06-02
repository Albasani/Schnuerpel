#!/usr/bin/perl -sw
#
# $Id: make-posts-per-month-stats.pl 651 2012-01-04 13:39:02Z alba $
#
# Copyright 2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
use strict;
use Carp qw( confess );
use Data::Dumper qw( Dumper );

use Schnuerpel::YearMonthGroupID qw(
  &CACHE_FILENAME
  &calc_totals
  &read_cache_file
  &report_all 
);

use constant USAGE =>
  "USAGE: make-post-stats.pl { option }\n" .
  "OPTIONS:\n" .
  "  -help            ... write this message\n" .
  "  -dir=<string>    ... default is current directory\n"
  ;

use constant DEBUG => 1;
use constant DEFAULT_DIR => '.';

######################################################################
sub get_max_mtime($@)
######################################################################
{
  my $dir = shift || confess;
  my $result = 0;
  for my $file(@_)
  {
    my $path = $dir . '/' . $file;
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime,
      $mtime, $ctime, $blksize, $blocks) = stat($path);
    if (defined($mtime))
    {
      if ($mtime > $result) { $result = $mtime; }
      if (DEBUG > 1) { printf "%9d %s\n", $mtime, $path; }
    }
    elsif (DEBUG)
    {
      printf "%s does not exist\n", $path;
    }
  }
  return $result;
}

######################################################################
sub enum_groups($$$)
######################################################################
{
  my $month_dir = shift || confess;
  my $rh_gi = shift || confess;
  my $mtime_summary = shift || confess;

  my $min_mtime = 0;
  my $glob_pattern = $month_dir . '/*/' . CACHE_FILENAME;
  my $group_pattern = '.*/([^/]+)/' . CACHE_FILENAME . '$';

  my $rh_group_totals = {};
  my $rh_hierarchy_totals = {};

  my @glob_group_cache = glob($glob_pattern);
  for my $group_cache(@glob_group_cache)
  {
    if ($group_cache !~ m#$group_pattern#o)
    {
      printf "Warning: %s does not match pattern '/group/%s'\n",
        CACHE_FILENAME, $group_cache;
      next;
    }
    my $group = $1;
    my $rh_id_attribute = ($rh_gi->{$group} ||= {});

    $rh_group_totals->{'.posts'} = read_cache_file(
      file_name => $group_cache,
      rh_id_attribute => $rh_id_attribute
    );

    calc_totals(
      'rh_id_attribute' => $rh_id_attribute,
      'rh_group_totals' => $rh_group_totals->{$group} = {},
      'rh_hierarchy_totals' => $rh_hierarchy_totals
    );

    my $mtime = $rh_id_attribute->{'.cache.mtime'} || confess;
    if ($mtime < $min_mtime) { $min_mtime = $mtime; }
  }

  # print Dumper($rh_group_totals); die;
  # print Dumper($rh_hierarchy_totals); die;

  if ($min_mtime < $mtime_summary)
  {
    report_all(
      'dir_name' => $month_dir,
      'rh_group_count' => $rh_group_totals,
      'rh_hierarchy_totals' => $rh_hierarchy_totals
    );
  }

  return $min_mtime;
}

######################################################################
sub enum_months($)
######################################################################
{
  my $month_dir = shift || confess;

  my $rh_ymgi;
  my @month_dir = glob($::dir . '/[0-9][0-9][0-9][0-9]/[0-9][0-9]');
  for my $month_dir(@month_dir)
  {
    if (! -d $month_dir)
    {
      printf "Warning: %s is not a directory\n", $month_dir;
      next;
    }
    if ($month_dir !~ m#/(\d\d\d\d)/(\d\d)$#)
    {
      printf "Warning: %s does not match /year/month/ pattern\n", $month_dir;
      next;
    }
    my $year = $1;
    my $month = $2;
    my $mtime_summary = get_max_mtime($month_dir,
      'clients.txt', 'paths.txt', 'posts.txt');

    my $rh_gi = $rh_ymgi->{$year}->{$month} ||= {};
    my $mtime_group = enum_groups($month_dir, $rh_gi, $mtime_summary);
  }
}

######################################################################
# MAIN
######################################################################

if (!$::dir) { $::dir = DEFAULT_DIR; }
if (!$::help) { $::help = undef; }
if ($::help) { print USAGE; exit; }

enum_months($::dir);
