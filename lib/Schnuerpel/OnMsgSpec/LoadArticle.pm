######################################################################
#
# $Id: LoadArticle.pm 622 2011-10-13 19:31:12Z root $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Implements interface "on_msg_spec"
# $msg_spec is used with Schnuerpel::NNTP::load_article
# Uses interface "on_article"
#
######################################################################

package Schnuerpel::OnMsgSpec::LoadArticle;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use Net::NNTP();
use News::Article();
use Schnuerpel::NNTP qw( load_article );

use constant DEBUG => 1;

######################################################################
sub new($@)
######################################################################
# Positional parameters:
#   proto
# Named parameters:
#   nntp     ... Net::NNTP
#   delegate ... object that implememts on_article
#   scope    ... string, either 'head' or 'article', defaults to 'article'
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = { @_ };
  bless ($self, $class);

  $self->{'nntp'} || confess 'Missing parameter "nntp"';
  $self->{'delegate'} || confess 'Missing parameter "delegate"';
  $self->{'scope'} ||= 'article';

  return $self;
}

######################################################################
sub on_msg_spec($$;$)
######################################################################
{
  my $self = shift || confess 'Missing parameter $self';
  my $msg_spec = shift || confess 'Missing parameter $msg_spec';
  my $group = shift;

  my Net::NNTP $nntp = $self->{'nntp'} || confess 'No $self->{"nntp"}';
  my $delegate = $self->{'delegate'} || confess 'No $self->{"delegate"}';
  my $scope = $self->{'scope'} || confess 'No $self->{"scope"}';

  if (ref($msg_spec) eq 'ARRAY')
  { # Message specification is range of message numbers.
    my $low = $msg_spec->[0];
    my $high = $msg_spec->[1];
    if (DEBUG)
    {
      printf "# OnMsgSpec::LoadArticle group=%s low=%d high=%d\n",
	$group, $low, $high;
    }
    for(my $i = $low; $i <= $high; ++$i)
    {
      my ( $article, $lines, $bytes ) =
	load_article($nntp, $i, $scope);
      defined($article) || next;
      $delegate->on_article(
        'article' => $article,
        'bytes' => $bytes,
        'group' => $group,
        'lines' => $lines,
      );
    }
  }
  else
  { # Message specification is message number or message ID.
    if (DEBUG)
    {
      printf "# OnMsgSpec::LoadArticle group=%s msg_spec=%d\n",
	$group, $msg_spec;
    }
    my ( $article, $lines, $bytes ) =
      load_article($nntp, $msg_spec, $scope);
    defined($article) || next;
    $delegate->on_article(
      'article' => $article,
      'bytes' => $bytes,
      'group' => $group,
      'lines' => $lines
    );
  }
}

######################################################################
1;
######################################################################
