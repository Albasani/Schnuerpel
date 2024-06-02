######################################################################
#
# $Id: MakeCancel.pm 619 2011-09-28 09:53:43Z alba $
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
# Implements interface "on_article"
#
######################################################################

package Schnuerpel::OnArticle::MakeCancel;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use News::Article();

use Schnuerpel::INN::CancelLock qw(
  calc_cancel_key
  verify_cancel_key
);

use constant DEBUG => 0;

######################################################################
sub new($@)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = { @_ };
  bless ($self, $class);

  return $self;
}

######################################################################
sub on_article($@)
######################################################################
# Named parameters
# - article   ... reference to News::Article
# - group     ... Value of header "Newsgroups" (string)
# - rh_pragma ... reference to hash
#                 key is string, value is string
# - original_newsgroups ... string, optional
######################################################################
{
  my $self = shift || confess;
  my %param = @_;

  my News::Article $article = $param{'article'} || confess 'Missing parameter "article"';
  my $group = $param{'group'} || confess 'Missing parameter "group"';
  my $rh_pragma = $param{'rh_pragma'} || confess 'Missing parameter "rh_pragma"';

  if (DEBUG)
  {
    while(my ($key, $value) = each %$rh_pragma)
    {
      printf "# %s=[%s]\n", $key, $value;
    }
  }

  my $org_id = $article->header('Message-ID') ||
    confess 'No "Message-ID" in $article->header';
  $org_id =~ m#^<(.*)>$# ||
    confess 'Invalid syntax of Message-ID ' . $org_id; 
  my $new_id = "<cancel.$1>";


  # send-queue.pl requires the "Newsgroups:" header immediately
  # after the POST command.
  printf "POST\n";
  printf "Newsgroups: %s\n", $group;

  my $org_group = $param{'original_newsgroups'};
  if ($org_group)
  {
    printf "X-Original-Newsgroups: %s\n", $org_group;
  }

  my $cancel_lock = $article->header('Cancel-Lock');
  if ($cancel_lock)
  {
    my $user = $rh_pragma->{'user'} ||
      die "Cancel-Lock is set, but user pragma not.\n";
    my $key = 'sha1:' . calc_cancel_key($user, $org_id);
    my $msg = verify_cancel_key($key, $cancel_lock, $org_id);
    if ($msg) { die $msg; }
    printf "Cancel-Key: %s\n", $key;
  }

  # man perlvar
  # $^V ... The revision, version, and subversion of the Perl
  #         interpreter, represented as a "version" object.
  printf "User-Agent: perl %vd\n", $^V;

  printf "Content-Type: %s\n",
    $rh_pragma->{'content_type'} || 'text/plain; charset=ISO-8859-1';
  printf "Subject: cmsg cancel %s\n", $org_id;
  printf "X-Original-Subject: %s\n", $article->header('Subject');

  printf "Control: cancel %s\n", $org_id;
  printf "Message-Id: %s\n", $new_id;


  my $type = $rh_pragma->{'type'} || 'spam';
  if ($type eq 'admin-cancel')
  {
    printf "From: %s\n", $article->header('From');
    print "\nCancelled by local administrator.\n";
  }
  else
  {
  #  printf "Reply-To: %s <%s>\n", NAME, MAIL;
  # printf "X-Canceled-By: %s <%s>\n", NAME, MAIL;
  # # printf "Approved: <%s>\n", MAIL;
  # printf "From: %s\n", $$f{from};
  # printf "Path: cyberspam!rosbot\n";
  }

  # printf "%s\n%s.\n", $headers->{EXTRA_HEADERS}, $body;

  print ".\n";
}

######################################################################
1;
######################################################################
