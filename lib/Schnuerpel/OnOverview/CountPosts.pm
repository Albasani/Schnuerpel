######################################################################
#
# $Id: CountPosts.pm 621 2011-10-13 19:30:56Z root $
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
# Implements interface "on_overview"
#
######################################################################

package Schnuerpel::OnOverview::CountPosts;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
  &REQUIRED_OVERVIEW_FIELDS
);

use strict;
use Carp qw( confess );
use Date::Parse();
use Net::NNTP();
use Schnuerpel::NNTP qw( load_headers );
use Schnuerpel::NewsArticle qw( get_posting_timestamp );

use constant REQUIRED_OVERVIEW_FIELDS => [ 'Date:', 'Message-ID:' ];

sub on_overview_without_delegate($@);

######################################################################
sub new($@)
# Positional parameters:
#   proto
# Named parameters:
#   rh_field_to_index
#   rh_year_month_group_id (optional)
#   on_article_delegate (optional) 
#   nntp (optional) 
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = { @_ };
  bless ($self, $class);

  $self->{'rh_year_month_group_id'} ||= {};
  my $rh_field_to_index = $self->{'rh_field_to_index'} || confess;

  # Index values can be zero
  $self->{'id_index'} = $rh_field_to_index->{'Message-ID:'};
  defined($self->{'id_index'}) || confess
    'Undefined $rh_field_to_index->{"Message-ID:"}';

  $self->{'bytes_index'} = $rh_field_to_index->{'Bytes:'};
  defined($self->{'bytes_index'}) || confess
    'Undefined $rh_field_to_index->{"Bytes:"}';

  $self->{'lines_index'} = $rh_field_to_index->{'Lines:'};
  defined($self->{'lines_index'}) || confess
    'Undefined $rh_field_to_index->{"Lines:"}';

  $self->{'date_index'} = $rh_field_to_index->{'Date:'};
  defined($self->{'date_index'}) || confess
    'Undefined $rh_field_to_index->{"Date:"}';

  return $self;
}

######################################################################
sub get_rh_attributes($$$)
######################################################################
{
  my $self = shift || confess;
  my $time = shift || confess;
  my $group = shift || confess;
  my $id = shift || confess;

  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst)
    = localtime($time);
  $month++;
  $year += 1900;

  return
    $self->{'rh_year_month_group_id'}->
    {$year}->
    {$month}->
    {$group}->
    {$id} ||= {};
}

######################################################################
sub on_overview($@)
# Named parameters:
#   group      ... string
#   article_id ... string or integer
#   ra_fields  ... 
######################################################################
{
  my $self = shift || confess;
  my %param = @_;

  my $ra_fields = $param{'ra_fields'} || confess 'Missing parameter "ra_fields"';
  my $group = $param{'group'} || confess 'Missing parameter "group"';

  my $date_str = $ra_fields->[ $self->{'date_index'} ] || confess;
  my $id = $ra_fields->[ $self->{'id_index'} ] || confess;

  my $rh_attributes;
  my $time = Date::Parse::str2time($date_str);
  if (defined($time))
  {
    $self->{'rh_id'}->{$id}++;
    $rh_attributes = $self->get_rh_attributes($time, $group, $id);
  }
  else
  {
    warn sprintf("Can't decode date string. group=%s id=%s date=%s",
      $group, $id, $date_str);
    return;
  }

  my $bytes_index = $self->{'bytes_index'};
  if (defined($bytes_index))
  {
    $rh_attributes->{'bytes'} = $ra_fields->[ $bytes_index ];
    defined($rh_attributes->{'bytes'}) || confess;
  }

  my $lines_index = $self->{'lines_index'};
  if (defined($lines_index))
  {
    $rh_attributes->{'lines'} = $ra_fields->[ $lines_index ];
    defined($rh_attributes->{'lines'}) || confess;
  }
}

######################################################################
sub get_year_month_group_id($)
######################################################################
{
  my $self = shift || confess;
  return $self->{'rh_year_month_group_id'};
}

######################################################################
1;
######################################################################
