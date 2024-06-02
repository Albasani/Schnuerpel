#
# $Id: Access.pm 509 2011-07-20 13:55:30Z alba $
#
# Copyright 2010 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# See etc/auth for usage and configuration.
#
######################################################################

package Schnuerpel::INN::Access;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &log_access_hash
  &get_max_rate_factor
);
use strict;

use Carp qw( confess );

######################################################################
# configuration
######################################################################

use constant DEBUG => 1;

######################################################################
sub log_access_hash($)
######################################################################
{
  my $r_access = shift || confess;

  my @value;
  for my $key(
    'access',
    'max_rate',
    'read',
    'users',
  )
  {
    my $value = $r_access->{$key};
    if ($value) { push(@value, $key . '=' . $value); }
  }

  INN::syslog('N', join(' ', @value));
}

######################################################################
sub get_max_rate_factor($$)

# if ($procs_blocked > 5) { return MAX_RATE_EMERGENCY; }
# if ($procs_blocked > 4) { return MAX_RATE_EMERGENCY * 2; }
# if ($procs_blocked > 3) { return MAX_RATE_EMERGENCY * 4; }
#
# get_max_rate_factor(4, 6)
######################################################################
{
  # on error 1 is returned
  # if load is above equal $emergency_load then 1 is returned
  # if load is below $unlimited_load then undef is returned
  my $unlimited_load = shift;
  my $emergency_load = shift;

  my $file;
  if (!open($file, '<', '/proc/stat')) { return 1; }

  my $procs_blocked;
  while(my $line = <$file>)
  {
    if ($line =~ m/^procs_blocked (\d+)/)
    {
      $procs_blocked = $1;
    }
  }

  if (!defined($procs_blocked)) { return 1; }
  if ($procs_blocked >= $emergency_load) { return 1; }
  if ($procs_blocked < $unlimited_load) { return undef; }

  return $emergency_load - $procs_blocked;
}

######################################################################
1;
######################################################################
