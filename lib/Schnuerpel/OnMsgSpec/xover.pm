######################################################################
#
# $Id: xover.pm 553 2011-08-08 23:03:13Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Implements interface "on_msg_spec"
# $msgspec is used with Net::NNTP::xover
# Uses interface "on_overview"
#
######################################################################

package Schnuerpel::OnMsgSpec::xover;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use Net::NNTP();
use Schnuerpel::Overview qw( get_overview_indexes );

use constant DEBUG => 0;

######################################################################
sub new($$$;$)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  $self->{'nntp'} = shift() || confess 'Missing parameter "nntp"';
  $self->{'delegate'} = shift() || confess 'Missing parameter "delegate"';
  my $rh_field_to_index = shift;
  if ($rh_field_to_index)
  {
    my @fields = keys(%$rh_field_to_index);
    $self->{'max_overview_index'} = $#fields;
  }

  return $self;
}

######################################################################
sub get_delegate($)
######################################################################
{
  my $self = shift || confess 'Missing parameter $self';
  return $self->{'delegate'} || confess 'No $self->{delegate}';
}

######################################################################
sub msgspec_as_string($)
######################################################################
{
  my ( $msgspec ) = @_;
  return ref($msgspec) eq 'ARRAY'
  ? join('-', @$msgspec)
  : $msgspec;
}

######################################################################
sub on_msg_spec($$;$)
######################################################################
{
  my $self = shift || confess 'Missing parameter $self';
  my $msgspec = shift || confess 'Missing parameter $msgspec';
  my $group = shift;

  if (DEBUG)
  {
    printf "# OnMsgSpec::xover [%s] %s\n",
      $group, msgspec_as_string($msgspec);
  }

  my Net::NNTP $nntp = $self->{'nntp'} || confess "No nntp";

  my $rh_article_to_overview = $nntp->xover($msgspec);
  if (!$rh_article_to_overview)
  {
    die sprintf(
      "xover(%s) returned undef: %s",
      msgspec_as_string($msgspec), $nntp->message()
    );
  }

  my $expected_max_index = $self->{'max_overview_index'};
  while(my ($article_id, $ra_fields) = each %$rh_article_to_overview)
  {
    if (DEBUG) { printf "on_msg_spec %s\n", $article_id; }
    if ($#$ra_fields != $expected_max_index)
    {
      die sprintf(
	"xover(%d) returned broken result (%s): %s",
	$article_id,
	join(", ", @$ra_fields),
	$nntp->message()
      );
    }
    $self->{'delegate'}->on_overview(
      'group' => $group,
      'article_id' => $article_id,
      'ra_fields' => $ra_fields
    );
  }
}

######################################################################
1;
######################################################################
