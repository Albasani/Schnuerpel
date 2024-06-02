#!/usr/bin/perl -sw
#
# $Id: count-posts-per-month.pl 635 2011-12-30 18:04:48Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
use strict;
use Carp qw( confess );
# use Data::Dumper qw( Dumper );

use Schnuerpel::ReconnectingNNTP();
use Schnuerpel::NewsrcNNTP qw(
  enum_newsrc_range
  get_newsrc
);
use Schnuerpel::YearMonthGroupID qw(
  &mkdir_if_not_exist
  &report_all
  &update_cache_file
);
use Schnuerpel::OnOverview::CountPosts();
use Schnuerpel::OnArticle::CountPosts();
use Schnuerpel::OnMsgSpec::xover();
use Schnuerpel::OnMsgSpec::LoadArticle();
use Schnuerpel::Overview qw( &get_overview_indexes );
use Schnuerpel::HeaderList qw( enum_headers_file );

use constant DEBUG => 1;
use constant DEFAULT_GROUPS => 'at.*';
# 'comp.*,humanities.*,misc.*,news.*,rec.*,sci.*,soc.*,talk';
use constant DEFAULT_DIR => '.';
use constant NEWSRC_FILE => 'count.newsrc';
use constant DEFAULT_METHOD => 'overview';

use constant USAGE =>
  "USAGE: count-posts-per-month.pl { option }\n" .
  "OPTIONS:\n" .
  "  -help            ... write this message\n" .
  "  -groups=<string> ... comma separated list of patterns\n" .
  "	default: " . DEFAULT_GROUPS . "\n" .
  "  -dir=<string>    ... default is current directory\n" .
  "  -method=<string> ... choose how information is gathered\n" .
  "     overview      ... use xover (fast, only count and size)\n" .
  "     article       ... load full article (slow, full stats)\n" .
  "     headerfile    ... load article headers from STDIN\n" .
  "     default: " . DEFAULT_METHOD . "\n"
  ;

######################################################################
sub get_count_newsrc($$;$)
######################################################################
{
  my $nntp = shift || confess;
  my $dir = shift || confess;
  my $groups = shift;

  my $filename = $::dir . '/' . NEWSRC_FILE;
  my News::Newsrc $newsrc = get_newsrc(
    $nntp, $filename, $groups
  );
  if (!$newsrc) { die 'Can\'t load file ' . $filename; }
  return $newsrc;
}

######################################################################
sub new_oms_xover($)
######################################################################
{
  my $nntp = shift || confess;

  my $rh_field_to_index = get_overview_indexes(
    $nntp,
    Schnuerpel::OnOverview::CountPosts::REQUIRED_OVERVIEW_FIELDS
  );
  if (DEBUG)
    { printf "# Overview: %s\n", join(', ', keys(%$rh_field_to_index)); }

  my $oo_countposts = Schnuerpel::OnOverview::CountPosts->new(
    'rh_field_to_index' => $rh_field_to_index
  );
  return Schnuerpel::OnMsgSpec::xover->new(
    $nntp, $oo_countposts, $rh_field_to_index
  );
}

######################################################################
sub enum_newsrc_article_count($$)
######################################################################
{
  my $nntp = shift || confess;
  my $newsrc = shift || confess;

  my $oa_countposts = Schnuerpel::OnArticle::CountPosts->new();
  my $ymgi = $oa_countposts->get_year_month_group_id();
  defined($ymgi) || confess;

  my $oms_load = Schnuerpel::OnMsgSpec::LoadArticle->new(
    'nntp' => $nntp,
    'delegate' => $oa_countposts,
    'scope' => 'article'
  );

  eval { enum_newsrc_range($nntp, $oms_load, $newsrc); };
  if ($@) { warn $@; }
  $newsrc->save();

  return $ymgi;
}

######################################################################
sub enum_newsrc_xover_count($$)
######################################################################
{
  my $nntp = shift || confess;
  my $newsrc = shift || confess;

  my $oms_xover = new_oms_xover($nntp);

  eval { enum_newsrc_range($nntp, $oms_xover, $newsrc); };
  if ($@) { warn $@; }
  $newsrc->save();

  my $ymgi = $oms_xover->get_delegate()->get_year_month_group_id();
  defined($ymgi) || confess;
  return $ymgi;
}

######################################################################
sub enum_file_headers_count($)
######################################################################
{
  my $groups = shift;
  $groups =~ s#\.#\\.#g;	# escape dots
  $groups =~ s#\*#.*#g;		# replace '*' with '.*'
  $groups =~ s#,#\$|^#g;	# handle multiple patterns
  $groups = '^' . $groups . '$';

  my $oa_countposts = Schnuerpel::OnArticle::CountPosts->new(
    'match_group' => $groups
  );
  my $ymgi = $oa_countposts->get_year_month_group_id();
  defined($ymgi) || confess;

  enum_headers_file(delegate => $oa_countposts);
  return $ymgi;
}

######################################################################
sub process_ymgi($)
######################################################################
{
  my $rh_ymgi = shift || confess 'Missing parameter $rh_ymgi';

  while(my ($year, $rh_mgi) = each %$rh_ymgi)
  {
    my $year_dir = sprintf('%s/%04d', $::dir, $year);
    mkdir_if_not_exist($year_dir);
    while(my ($month, $rh_gi) = each %$rh_mgi)
    {
      my $month_dir = sprintf('%s/%02d', $year_dir, $month);
      mkdir_if_not_exist($month_dir);

      my $rh_hierarchy_totals = {};
      my $rh_group_totals = {};
      while(my ($group, $rh_i) = each %$rh_gi)
      {
	my $group_dir = sprintf('%s/%s', $month_dir, $group);
        mkdir_if_not_exist($group_dir);
	my $rh_total = update_cache_file(
	  'dir_name' => $group_dir,
	  'rh_id_attribute' => $rh_i,
	  'rh_group_totals' => $rh_group_totals->{$group} = {},
	  'rh_hierarchy_totals' => $rh_hierarchy_totals
        );
      }

      report_all(
        'dir_name' => $month_dir,
	'rh_group_count' => $rh_group_totals,
	'rh_hierarchy_totals' => $rh_hierarchy_totals
      );
    }
  }
}

######################################################################
sub connect_nntp($$)
######################################################################
{
  my $dir = shift;
  my $groups = shift;

  my $rcnntp = Schnuerpel::ReconnectingNNTP->new();
  if (DEBUG)
  {
    my $s = $rcnntp->{'signature'}; chomp($s);
    printf "# %s\n", $s;
  }
  my News::Newsrc $newsrc = get_count_newsrc($rcnntp, $dir, $groups);
  return ($rcnntp, $newsrc);
}

######################################################################
# MAIN
######################################################################

if (!$::dir) { $::dir = DEFAULT_DIR; }
if (!$::groups) { $::groups = DEFAULT_GROUPS; }
if (!$::help) { $::help = undef; }
if (!$::method) { $::method = DEFAULT_METHOD; }
if ($::help) { print USAGE; exit; }

my $rh_ymgi;
if ($::method eq 'overview')
{
  my ($rcnntp, $newsrc) = connect_nntp($::dir, $::groups);
  $rh_ymgi = enum_newsrc_xover_count($rcnntp, $newsrc);
}
elsif ($::method eq 'article')
{
  my ($rcnntp, $newsrc) = connect_nntp($::dir, $::groups);
  $rh_ymgi = enum_newsrc_article_count($rcnntp, $newsrc);
}
elsif ($::method eq 'headerfile')
{
  $rh_ymgi = enum_file_headers_count($::groups);
}
else
{
  die "Invalid value for option -method.";
}

process_ymgi($rh_ymgi);
# print Data::Dumper::Dumper( $rh_ymgi );
