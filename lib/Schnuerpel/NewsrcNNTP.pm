######################################################################
#
# $Id: NewsrcNNTP.pm 553 2011-08-08 23:03:13Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::NewsrcNNTP;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &get_newsrc
  &subscribe
  &enum_newsrc_range
);

use strict;
use Carp qw( confess );
use Net::NNTP();
use News::Newsrc();
use Data::Dumper qw( Dumper );

use constant DEBUG => 0;

######################################################################
sub subscribe($;$$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my News::Newsrc $newsrc = shift;
  my $r_group_pattern = shift;

  my @group;
  if (defined($r_group_pattern))
  {
    for my $pattern(@$r_group_pattern)
    {
      if (DEBUG > 1) { printf "Net::NNTP::active(%s) ...\n", $pattern; }
      my $r_group = $nntp->active($pattern);
      push @group, keys(%$r_group);
    }
  }
  else
  {
    my $r_group = $nntp->list();
    @group = map { $_ . ':' } keys(%$r_group);
  }

  if (defined($newsrc))
  {
    for my $group(@group)
    {
      if (DEBUG > 1) { printf "News::Newsrc::subscribe(%s) ...\n", $group; }
      $newsrc->subscribe($group);
      if (DEBUG > 1 && !$newsrc->subscribed($group))
      {
	printf "News::Newsrc::subscribe failed on %s\n", $group;
      }
    }
  }
  else
  {
    $newsrc = News::Newsrc->new();
    $newsrc->import_rc( sort(@group) );
  }

  return $newsrc;
}

######################################################################
sub get_newsrc($$;$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my $filename = shift || confess;
  my $groups = shift;

  my News::Newsrc $newsrc = News::Newsrc->new();
  my $ok = $newsrc->load($filename);

  if (defined($groups))
  {
    my @groups = split(/,/, $groups);
    subscribe($nntp, $newsrc, \@groups);
    $newsrc->save_as($filename);
    $ok = 1;
  }

  return $ok ? $newsrc : undef;
}

######################################################################
sub enum_newsrc_range($$$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my $delegate = shift || confess;
  my $newsrc = shift || confess;

  my @group = $newsrc->sub_groups();
  for my $group(@group)
  {
    my ( $nr, $low, $high, $name ) = $nntp->group($group);
    unless(defined($nr))
    {
      local $| = 1;
      warn "Can't change into group $group, code=" . $nntp->code() .
	', message=' . $nntp->message();
      $newsrc->del_group($group) || confess "del_group($group)";
      next;
    }

    if ($low > $high)
    {
      if (DEBUG) { warn "Group $group is empty. low=$low high=$high"; }
      next;
    }
    
    # This returns an array of article numbers.
    # But for xpat we prefer a range.
    
    # sort article IDs numerically
    my @have_to_do = sort { $a <=> $b } (
      $newsrc->unmarked_articles($group, $low, $high)
    );

    my $max_index = $#have_to_do;

    if (DEBUG)
    {
      local $| = 1;
      printf 'enum_newsrc_range group=%s low=%d high=%d #=%d' . "\n",
	$group, $low, $high, $max_index;
    }

    next if ($max_index < 0);
    my $min = $have_to_do[0];
    my $max = $have_to_do[ $max_index ];

    if (DEBUG)
    {
      local $| = 1;
      printf 'enum_newsrc_range min=%d max=%d %d %d' . "\n",
	$min, $max, $#have_to_do < 0, $min > $max
    }

    next if ($min > $max);
    $delegate->on_msg_spec([ $min, $max ], $group);
    $newsrc->mark_range($group, $min, $max);
  }
}

######################################################################
1;
######################################################################
