#!/usr/bin/perl -ws
#
# $Id: make-iptables-redirect.pl 489 2011-03-13 18:52:50Z alba $
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

use Data::Dumper;

use constant FORMAT =>
  '$IPTABLES -t nat -A REDIRECT_nntp -p tcp -s %s ' .
  "-j REDIRECT --to-ports %s\n";

######################################################################
# MAIN
######################################################################
load_innshellvars();

my $delegate = new Schnuerpel::INN::ConfigFile::DGResolveHostname();
my $tree = eval
{
  my $r = new Schnuerpel::INN::ConfigFile::Incoming( $delegate );
  $r->open($inn::pathetc . '/incoming.conf');
  $r->read();
};

my $name_to_addr = $delegate->get_name_to_addr();

my $rh_peer = $tree->{'peer'};
if ($rh_peer)
{
  while(my ($peer, $rh_param) = each %$rh_peer)
  {
    if ($peer eq 'ME') { next; }
    my $comment = $rh_param->{'comment'};
    if (defined($comment) && $comment eq $inn::port) { next; }

    my $hostname_param = $rh_param->{'hostname'};
    if (!$hostname_param) { next; }

    for my $hostname( split(/\s*,\s*/, $hostname_param) )
    {
      my $rh_addr = $name_to_addr->{$hostname};
      if (!$rh_addr) { next; }
      while(my ($addr, $dummy) = each %$rh_addr)
      {
        if ($addr =~ /:/) { next; } # ignore IPv6
        printf FORMAT, $addr, $inn::port;
      }
    }
  }
}
