######################################################################
#
# $Id: DGResolveHostname.pm 510 2011-07-20 13:56:21Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::ConfigFile::DGResolveHostname;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw( $new );
use strict;

use Net::DNS::Resolver;

sub resolve_cname($$$$);

######################################################################
sub new($)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  =
  {
    'ra_peer' => [],
    'rhrh_name_to_addr' => {},
    'rhrh_addr_to_name' => {},
    'resolver' => Net::DNS::Resolver->new(),
    'ra_query_type' => [ 'A' ],
  };
  bless($self, $class);

  return $self;
}

######################################################################
sub set_query_type($@)
######################################################################
{
  my $self = shift || die 'No $self';
  $self->{ra_query_type} = \@_;
}

######################################################################
sub add_parameter($$$$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $rh_node = shift || die 'No $rh_node';
  my $ident = shift || die 'No $rh_node';
  my $value = shift;

  $rh_node->{$ident} = $value;

  if ($ident eq 'peer')
  {
    my $ra_peer = $self->{ra_peer};
    push @$ra_peer, $value;
  }
  elsif ($ident eq 'hostname' || $ident eq 'ip-name')
  {
    my @hostname = split(/\s*,\s*/, $value);
    $self->lookup_hostname(\@hostname);
  }
}

######################################################################
sub get_name_to_addr($)
######################################################################
{
  my $self = shift || die 'No $self';
  return $self->{rhrh_name_to_addr} || die;
}

######################################################################
sub get_addr_to_name($)
######################################################################
{
  my $self = shift || die 'No $self';
  return $self->{rhrh_addr_to_name} || die;
}

######################################################################
sub resolve_cname($$$$)
######################################################################
{
  my $resolver = shift || die 'No $resolver';
  my $cname = shift || die 'No $cname';
  my $query_type = shift || die 'No $query_type';
  my $ra_result = shift || die 'No $ra_result';

  my Net::DNS::Packet $packet = $resolver->query($cname, $query_type);
  if (!$packet)
  {
    printf STDERR
      "Net::DNS::Packet::query failed for hostname %s, type %s\n",
      $cname, $query_type;
    return $ra_result;
  }
  my @answer = $packet->answer();
  undef $packet;

  for my $answer(@answer)
  {
    if ($answer->class() ne 'IN')
    {
      printf STDERR "Invalid class for %s\n", $answer->string;
      next;
    }

    my $type = $answer->type();
    if ($type eq 'A' || $type eq 'AAAA')
    {
      push @$ra_result, $answer->rdatastr();
    }
    elsif ($type eq 'CNAME')
    {
      resolve_cname($resolver, $answer->rdatastr(), $query_type, $ra_result);
    }
    else
    {
      printf STDERR "Invalid reply type for %s\n", $answer->string;
      next;
    }
  }
  return $ra_result;
}

######################################################################
sub lookup_hostname($$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $ra_hostname = shift || die 'No $ra_hostname';

  my $resolver = $self->{resolver} || die;
  my $rhrh_name_to_addr = $self->{rhrh_name_to_addr} || die;
  my $rhrh_addr_to_name = $self->{rhrh_addr_to_name} || die;
  my $ra_query_type = $self->{ra_query_type} || die;

  for my $hostname(@$ra_hostname)
  {
    my $rh_addr = ($rhrh_name_to_addr->{$hostname} ||= {});
    my @addr;
    for my $type( @$ra_query_type )
    {
      resolve_cname($resolver, $hostname, $type, \@addr);
    }
    for my $addr(@addr)
    {
      $rh_addr->{$addr} = undef;
      my $addr_to_name = ($rhrh_addr_to_name->{$addr} ||= {});
      $addr_to_name->{$hostname} = undef;
    }
  }
}

######################################################################
1;
######################################################################
