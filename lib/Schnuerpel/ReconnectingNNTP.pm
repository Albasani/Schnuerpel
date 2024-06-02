######################################################################
#
# $Id: ReconnectingNNTP.pm 610 2011-09-01 00:33:36Z alba $
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
# Wraps an interface if Net::NNTP.
#
######################################################################

package Schnuerpel::ReconnectingNNTP;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess croak );
use Net::NNTP();
use Schnuerpel::ConfigNNTP();

use constant DEBUG => 0;

######################################################################
sub new($@)
######################################################################
# Positional parameters:
#   proto
# Named parameters:
#   debug ... boolean, defaults to DEBUG
#   config ... Schnuerpel::ConfigNNTP, defaults to new instance
######################################################################
{
  my $proto = shift || confess;
  my %param = @_;

  my $debug = $param{'debug'} || DEBUG;
  my $config = $param{'config'} || Schnuerpel::ConfigNNTP->new();

  my ( $host, $port ) = $config->get_host();
  my ( $user, $pass ) = $config->read_authinfo();
  my $self =
  {
    'debug' => $debug,
    'host' => $host,
    'port' => $port,
    'user' => $user,
    'pass' => $pass
  };

  my $class = ref($proto) || $proto;
  bless ($self, $class);

  $self->connect();
  return $self;
}

######################################################################
sub connect($)
######################################################################
{
  my $self = shift || confess;

  my $host = $self->{'host'} || confess;
  my $port = $self->{'port'} || confess;
  my $user = $self->{'user'};
  my $pass = $self->{'pass'};

  my $nntp = Net::NNTP->new(
    Host => $host . ':' . $port,
    Debug => $self->{'debug'},
    Reader => 1
  );
  if (!$nntp)
  {
    die sprintf('Connection failed for host=%s port=%s',
      $host, $port);
  }

  # first message after connect is server signature
  $self->{'signature'} = $nntp->message();

  if ($user && !$nntp->authinfo($user, $pass))
  {
    die sprintf(
      'Error: Authentication failed for host=%s port=%s user=%s pass=%s',
      $host, $port, $user, $pass
    );
  }

  return $self->{'nntp'} = $nntp;
}


######################################################################
sub reconnect_after_error($$)
######################################################################
{
  my $self = shift || confess;
  my $method_name = shift || confess;

  my $nntp = $self->{'nntp'} || confess;
  my $code = $nntp->code();

  #  code=412, message=Not in a newsgroup

  if ($code == 0)	# No error
    { return 0; }

  elsif ($code == 423)	# No such article number
    { return 0; }
  elsif ($code == 599)	# Connection closed
  {
    return 0 if (!$self->connect());
    my $group_name = $self->{'group_name'};
    if ($group_name) { return $self->group($group_name); }
    return 1;
  }

  croak sprintf "Net::NNTP::%s failed, code=%d, message=%s",
    $method_name, $code, $nntp->message();
}

######################################################################
sub article($@)
######################################################################
{
  my $self = shift || confess;
  do
  {
    my $rc = $self->{'nntp'}->article(@_);
    if ($rc) { return $rc; }
  } while($self->reconnect_after_error('article'));
  return undef;
}

######################################################################
sub active($@)
######################################################################
{
  my $self = shift || confess;
  do
  {
    my $rc = $self->{'nntp'}->active(@_);
    if ($rc) { return $rc; }
  } while($self->reconnect_after_error('active'));
  return undef;
}

######################################################################
sub group($@)
######################################################################
{
  my $self = shift || confess;
  do
  {
    if (wantarray)
    {
      my @rc = $self->{'nntp'}->group(@_);
      if (@rc)
      {
        $self->{'group_name'} = $rc[3];
	return @rc;
      }
    }
    else
    {
      my $group_name = $self->{'nntp'}->group(@_);
      if ($group_name) { return $self->{'group_name'} = $group_name; }
    }
  } while($self->reconnect_after_error('group'));
  return undef;
}

######################################################################
sub overview_fmt($)
######################################################################
{
  my $self = shift || confess;
  do
  {
    my $rc = $self->{'nntp'}->overview_fmt();
    if ($rc) { return $rc; }
  } while($self->reconnect_after_error('overview_fmt'));
  return undef;
}

######################################################################
sub xover($$)
######################################################################
{
  my $self = shift || confess;
  do
  {
    my $rc = $self->{'nntp'}->xover(@_);
    if ($rc) { return $rc; }
  } while($self->reconnect_after_error('xover'));
  return undef;
}

######################################################################
1;
######################################################################
