######################################################################
#
# $Id: Overview.pm 511 2011-07-21 18:57:30Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::Overview;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &get_overview_indexes
  &get_overview_fields
);

use strict;
use Carp qw( confess );
use Net::NNTP();

use constant DEBUG => 0;
use constant DEFAULT_REQUIRED => [ 'Date:', 'Message-ID:' ];

######################################################################
sub get_overview_indexes($;$)
######################################################################
{
  my Net::NNTP $nntp = shift || die;
  my $ra_required = shift || DEFAULT_REQUIRED;

  my $ra_fmt = $nntp->overview_fmt();
  if (!$ra_fmt)
  {
    die sprintf("overview_fmt failed: %s\n", $nntp->message());
  }

  my $index = 0;
  my $rh_field_to_index;
  for my $field(@$ra_fmt)
  {
    $rh_field_to_index->{ $field } = $index;
    ++$index;
  }

  for my $field(@$ra_required)
  {
    if (!exists($rh_field_to_index->{ $field })) 
    {
      die "Field $field not found in overview. overview_fmt="
	. join(', ', @$ra_fmt);
    }
  }

  if (DEBUG)
    { printf "Overview fields: %s\n", join(', ', @$ra_fmt); }
  return $rh_field_to_index;
}

######################################################################
sub get_overview_fields($$;$)
######################################################################
{
  my Net::NNTP $nntp = shift || die;
  my $article_id = shift;
  my $expected_max_index = shift;

  die unless(defined($article_id));
  die unless($article_id >= 0);

  my $rh_article_to_overview = $nntp->xover($article_id);
  if (!$rh_article_to_overview)
  {
    die sprintf(
      "xover(%d) returned undef: %s",
      $article_id, $nntp->message()
    );
  }

  my $ra_fields = $rh_article_to_overview->{ $article_id };
  if (!defined($ra_fields))
  {
    die sprintf("xover(%d) failed: %s", $article_id, $nntp->message());
  }

  if ($expected_max_index)
  {
    if ($#$ra_fields != $expected_max_index)
    {
      die sprintf(
	"xover(%d) returned broken result (%s): %s",
	$article_id,
	join(", ", @$ra_fields),
	$nntp->message()
      );
    }
  }

  return $ra_fields;
}

######################################################################
1;
######################################################################
