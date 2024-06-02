######################################################################
#
# $Id: ConfigNNTP.pm 512 2011-07-21 19:17:25Z alba $
#
# Copyright 2007 - 2008 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::ConfigNNTP;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &get_host
  &new
  &read_authinfo
  &VERBOSE
);

use strict;
use Carp qw( confess );
use Net::Config qw(%NetConfig);

use constant VERBOSE => 0;

######################################################################
sub new($)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  {
    my $home = $ENV{'HOME'};
    unless(defined($home))
    {
      die "Undefined environment variable HOME";
    }
    $self->{home} = $home;
  }

  $self->{default_server} = shift();

  return $self;
}

######################################################################
sub get_host($;$)
######################################################################
{
  my $self = shift || confess;
  my $server = shift;

  if (!defined($server))
  {
    $server = $self->{default_server};
    if (!defined($server))
    {
      $server = $ENV{'NNTPSERVER'};
      if (!defined($server))
      {
	my $r = $NetConfig{'nntp_hosts'};
	if (defined($r) && $#$r >= 0)
	{
	  $server = $r->[0];
	}
	else
	{
	  die "Undefined environment variable NNTPSERVER";
	}
      }
      $self->{default_server} = $server;
    }
  }

  my $port = $self->{default_port};
  if (!defined( $port ))
  {
    $port = $ENV{'NNTPPORT'};
    $self->{default_port} = defined($port) ? $port : 119;
  }

  return ( $server, $self->{default_port} );
}

######################################################################
sub read_slrnrc($;$)
######################################################################
{
  my $self = shift || confess;
  my $server = shift;

  my $home = $self->{home} || confess;
  my $slrnrc = $home . '/.slrnrc';
  unless(-r $slrnrc)
  {
    die "File $slrnrc does not exist.";
  }

  my $port;
  ( $server, $port ) = $self->get_host($server);

  my $file;
  open($file, '<' . $slrnrc) || die "Can't open $slrnrc: $!";
  while(my $line = <$file>)
  {
    if ($line =~ m/
      ^ \s* nnrpaccess \s+
      ("?) $server \1 \s+
      ("?) ([^\s"]+) \2 \s+
      ("?) ([^\s"]+) \4
    /ox)
    {
      $self->{username} = $3;
      $self->{password} = $5;
    }
  }
  close($file);
}

######################################################################
sub read_authinfo($;$)
######################################################################
{
  my $self = shift || confess;
  my $server = shift;

  if ( !exists( $self->{username}) || !exists( $self->{password}) )
  {
    $self->read_slrnrc($server);
  }
  return ( $self->{username}, $self->{password} );
}

######################################################################
1;
######################################################################
