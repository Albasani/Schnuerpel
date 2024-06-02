######################################################################
#
# $Id: NNTP.pm 572 2011-08-15 16:59:08Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::NNTP;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &connect
  &enum_active
  &enum_group_hash
  &enum_newnews
  &load_article
  &load_headers
);

use strict;
use Carp qw( confess );
use Net::NNTP();

use Schnuerpel::ConfigNNTP qw( &VERBOSE );

use constant DEBUG => 0;
use constant MAXHEADS => 16 * 1024;
use constant MAXSIZE => 1024 * 1024;

######################################################################
sub connect(;$$)
######################################################################
{
  my $debug = shift;
  my $config = shift;

  if (!defined($debug))
    { $debug = DEBUG; }
  if (!defined($config))
    { $config = Schnuerpel::ConfigNNTP->new(); }

  my ( $host, $port ) = $config->get_host();
  my ( $user, $pass ) = $config->read_authinfo();

  my $nntp = Net::NNTP->new(
    Host => $host . ':' . $port,
    Debug => $debug,
    Reader => 1
  );
  unless(defined($nntp))
    { die "Can't connect to $host"; }

  # first message after connect is server signature
  my $signature = $nntp->message();

  unless( $nntp->authinfo($user, $pass) )
  {
    die sprintf(
      "Error: Authentication failed for host=%s\nuser=%s pass=%s",
      $host, $user, $pass
    );
  }

  my $postok = $nntp->postok();
  return {
    'debug' => $debug,
    'host' => $host,
    'nntp' => $nntp,
    'port' => $port,
    'signature' => $signature,
    'user' => $user,
    'postok' => $postok
  };
}

######################################################################
sub enum_group_hash($$;$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my $delegate = shift || confess;
  my $r_group = shift || confess;

  while(my ($group, $r_info) = each %$r_group)
  {
    $nntp->group($group) || die "Can't change into group $group";
    $delegate->on_msg_spec([ $r_info->[1], $r_info->[0] ], $group);
  }
}

######################################################################
sub enum_active($$;$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my $delegate = shift || confess;
  my $r_group_pattern = shift;

  if (defined($r_group_pattern))
  {
    for my $pattern(@$r_group_pattern)
      { enum_group_hash($nntp, $delegate, $nntp->active($pattern)); }
  }
  else
  {
    enum_group_hash($nntp, $delegate, $nntp->list());
  }
}

######################################################################
sub enum_newnews($$;$$)
######################################################################
{
  my Net::NNTP $nntp = shift || confess;
  my $delegate = shift || confess;
  my $r_group_pattern = shift;
  my $delta_seconds = shift;

  $r_group_pattern = [ '*' ] unless(defined($r_group_pattern));

  my $now = $nntp->date() || die "Error: Can't retrieve server date";
  my $seconds = (defined($delta_seconds))
  ? $now - $delta_seconds
  : 0;

  my $r_mid = $nntp->newnews($seconds, $r_group_pattern);
  for my $mid(@$r_mid)
  {
    $delegate->on_msg_spec($mid);
  }
}

######################################################################
sub load_article($$;$)
######################################################################
# Parameters:
# - $nntp     ... Net::NNTP
# - $msg_spec ... string or integer
# - $scope    ... string (optional), either 'article' or 'head'
#                 defaults to 'article'
######################################################################
{
  my Net::NNTP $nntp = shift || confess 'Missing parameter $nntp';
  my $msg_spec = shift; # number might be zero
  defined($msg_spec) || confess 'Missing parameter $msg_spec';
  my $scope = shift || 'article'; #

  my $r_lines = eval { return $nntp->$scope($msg_spec); };
  if ($@)
  {
    confess "Net::NNTP::$scope failed for $msg_spec\n$@";
  }
  elsif (!defined($r_lines))
  {
    return undef;
  }
  else
  {
    my $bytes = 0;
    for my $line(@$r_lines)
    {
      # line is terminated with '\n'
      # article size is calculated with "\r\n", though
      $bytes += length($line) + 1;
    }

    my $article = News::Article->new($r_lines, MAXSIZE, MAXHEADS)
    || confess "Can't create instance of News::Article";

    return ( $article, 1 + $#$r_lines, $bytes );
  }
}

######################################################################
sub load_headers($$)
######################################################################
{
  return load_article($_[0], $_[1], 'head');
}

######################################################################
1;
######################################################################
