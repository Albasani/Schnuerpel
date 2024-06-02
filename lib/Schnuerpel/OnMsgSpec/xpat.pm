######################################################################
#
# $Id: xpat.pm 553 2011-08-08 23:03:13Z alba $
#
# Copyright 2007-2009 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Implements interface "on_msg_spec".
# $range is used with Net::NNTP::xpat
# Uses interface "on_msg_spec".
#
######################################################################

package Schnuerpel::OnMsgSpec::xpat;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use Net::NNTP();

use constant DEBUG => 1;

######################################################################
sub new($$$$)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  $self->{'nntp'} = shift() || confess;
  $self->{'xpat_defs'} = shift() || confess;
  $self->{'delegate'} = shift() || confess "Parameter delegate missing";

  $self->{'xpat_checked'} = {};
  return $self;
}

######################################################################
sub range_as_string($)
######################################################################
{
  my ( $range ) = @_;
  return ref($range) eq 'ARRAY'
  ? join('-', @$range)
  : $range;
}

######################################################################
sub on_msg_spec($$;$)
######################################################################
{
  my $self = shift || confess;
  my $range = shift || confess;
  my $group = shift;

  if (DEBUG)
  {
    local $| = 1;
    printf "# OnMsgSpec::xpat [%s] %s\n",
      $group, range_as_string($range);
  }

  my Net::NNTP $nntp = $self->{'nntp'} || confess "No nntp";
  my $r_xpat_defs = $self->{'xpat_defs'} || confess "No xpat_defs";
  my $delegate = $self->{'delegate'} || confess "No delegate";
  my $r_xpat_checked = $self->{'xpat_checked'} || confess "No xpat_checked";

  for my $r_def(@$r_xpat_defs)
  {
    my $out = $nntp->xpat($r_def->[0], $r_def->[1], $range);
    unless(defined($out))
    {
      local $| = 1;
      warn 'xpat(' . range_as_string($range) . ') failed.';
      next;
    }

    if (DEBUG)
    {
      local $| = 1;
      my @k = keys(%$out);
      printf "# xpat(%s, %s) returned %d\n",
	$r_def->[0], $r_def->[1], $#k;
    }

    my $perl_expr = $r_def->[2];
    unless($perl_expr)
    {
      while(my ($article_number, $header) = each %$out)
      {
	next if ($r_xpat_checked->{$group}->{$article_number}++ > 0);
	$delegate->on_msg_spec($article_number, $group);
      }
      next;
    }

    while(my ($article_number, $header) = each %$out)
    {
      next if ($r_xpat_checked->{$group}->{$article_number}++ > 0);
      if ($header =~ m/$perl_expr/x)
      {
	$delegate->on_msg_spec($article_number, $group);
      }
      else
      {
        local $| = 1;
	warn "Perl RE does not match: [$header] [$perl_expr]";
      }
    }
  }
}

######################################################################
1;
######################################################################
