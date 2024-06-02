#!/usr/bin/perl -w
######################################################################
#
# $Id: HostList.pm 509 2011-07-20 13:55:30Z alba $
#
# Copyright 2010 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
package Schnuerpel::HostList;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &get_host_list
);

use strict;

use constant DEBUG_INN => 0;

######################################################################

my %loaded_module;

######################################################################
sub load($)
######################################################################
{
  my $module = shift || die;

  my $dir = $ENV{'SCHNUERPEL_VAR'};
  if ($dir)
  {
    my $found = grep { $_ eq $dir } @INC;
    push(@INC, $dir) if (!$found);
  }

  eval "use HostList::$module;";
  if (length($@) == 0)
  {
    no strict;
    my $r_update = eval '*{$HostList::' . $module . '::{"IP"}}{"CODE"}';
    return $r_update if defined($r_update); 
  }
  elsif(DEBUG_INN)
  {
    INN::syslog('W', "use HostList::$module failed: $@");
  }

  return sub { return undef; }
}

######################################################################
sub get_host_list($)
######################################################################
{
  my $module_name = shift || die;

  my $func = $loaded_module{$module_name};
  if (!defined($func))
  {
    $loaded_module{$module_name} = $func = load($module_name);
  }
  return $func->()
}

######################################################################
1;
######################################################################
