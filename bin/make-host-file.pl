#!/usr/bin/perl -ws
#
# $Id: make-host-file.pl 490 2011-03-13 18:53:02Z alba $
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
use Schnuerpel::INN::ShellVars qw( load_innshellvars );
use Schnuerpel::INN::ConfigFile::Incoming();
use Schnuerpel::INN::ConfigFile::Innfeed();
use Schnuerpel::INN::ConfigFile::DGResolveHostname();

######################################################################
# MAIN
######################################################################
load_innshellvars();

my $d = new Schnuerpel::INN::ConfigFile::DGResolveHostname();
$d->set_query_type('A', 'AAAA');
{
  my $r = new Schnuerpel::INN::ConfigFile::Incoming( $d );
  $r->open($inn::pathetc . '/incoming.conf');
  $r->read();
}
{
  my $r = new Schnuerpel::INN::ConfigFile::Innfeed( $d );
  $r->open($inn::pathetc . '/innfeed.conf');
  $r->read();
}

my $addr_to_name = $d->get_addr_to_name();
while(my ($addr, $rh_name) = each %$addr_to_name)
{
  while(my ($name, $dummy) = each %$rh_name)
  {
    printf "%-16s %s\n", $addr, $name;
  }
}
