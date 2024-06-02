######################################################################
#
# $Id: Innfeed.pm 510 2011-07-20 13:56:21Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::ConfigFile::Innfeed;
use base qw( Schnuerpel::INN::ConfigFile::Reader );
@EXPORT_OK = qw( $new );
use strict;

use constant PARAMETERS => {
  'article-timeout' => undef,
  'backlog-ckpt-period' => undef,
  'backlog-directory' => undef,
  'backlog-factor' => undef,
  'backlog-feed-first' => undef,
  'backlog-highwater' => undef,
  'backlog-limit' => undef,
  'backlog-limit-highwater' => undef,
  'backlog-newfile-period' => undef,
  'backlog-rotate-period' => undef,
  'bindaddress' => undef,
  'bindaddress6' => undef,
  'close-period' => undef,
  'connection-stats' => undef,
  'debug-level' => undef,
  'deliver' => undef,
  'dns-expire' => undef,
  'dns-retry' => undef,
  'drop-deferred' => undef,
  'dynamic-backlog-filter' => undef,
  'dynamic-backlog-high' => undef,
  'dynamic-backlog-low' => undef,
  'dynamic-method' => undef,
  'force-ipv4' => undef,
  'gen-html' => undef,
  'host-queue-highwater' => undef,
  'initial-connections' => undef,
  'initial-reconnect-time' => undef,
  'input-file' => undef,
  'ip-name' => undef,
  'log-file' => undef,
  'log-time-format' => undef,
  'max-connections' => undef,
  'max-queue-size' => undef,
  'max-reconnect-time' => undef,
  'min-queue-connection' => undef,
  'news-spool' => undef,
  'no-backlog' => undef,
  'no-check-filter' => undef,
  'no-check-high' => undef,
  'no-check-low' => undef,
  'password' => undef,
  'pid-file' => undef,
  'port-number' => undef,
  'response-timeout' => undef,
  'stats-period' => undef,
  'stats-reset' => undef,
  'status-file' => undef,
  'stdio-fdmax' => undef,
  'streaming' => undef,
  'use-mmap' => undef,
  'username' => undef,
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
