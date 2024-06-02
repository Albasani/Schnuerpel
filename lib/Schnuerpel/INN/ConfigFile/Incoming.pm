######################################################################
#
# $Id: Incoming.pm 510 2011-07-20 13:56:21Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::ConfigFile::Incoming;
use base qw( Schnuerpel::INN::ConfigFile::Reader );
@EXPORT_OK = qw( $new );
use strict;

use constant PARAMETERS => {
  'comment' => undef,
  'email' => undef,
  'hold-time' => undef,
  'hostname' => undef,
  'identd' => undef,
  'ignore' => undef,
  'max-connections' => undef,
  'nolist' => undef,
  'noresendid' => undef,
  'password' => undef,
  'patterns' => undef,
  'skip' => undef,
  'streaming' => undef,
};

######################################################################
sub new($;$)
######################################################################
{
  my $proto = shift;
  my $delegate = shift;

  my $class = ref($proto) || $proto;
  my $self  = { delegate => $delegate };
  bless($self, $class);

  return $self;
}

######################################################################
sub read($;$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $rh_node = shift || {};

  $self->read_peer_group_tree(PARAMETERS, $rh_node);
  my $token = $self->get_token();
  if (defined($token))
  {
    die $self->error_sprintf('Unexpected "%s" at end of file.', $token);
  }
  return $rh_node;
}

######################################################################
1;
######################################################################
