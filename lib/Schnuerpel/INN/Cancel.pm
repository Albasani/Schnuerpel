######################################################################
#
# $Id: Cancel.pm 509 2011-07-20 13:55:30Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::Cancel;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  $bad_cancel_hosts
  &check_local_path_id
  &handle_cancel
  &verify_cancel
);
use strict;

use Carp qw( confess );

use Schnuerpel::INN::CancelLock qw(
  verify_cancel_key
);

use Schnuerpel::Config qw(
  &CANCEL_MISSING_TARGET
  &CANCEL_ONLY_AUTHORIZED
  $GROUPS_ACCEPTING_ANY_CANCEL
  &LOCAL_PATH_ID
  &REJECT_INVALID_CANCEL
  &SAFE_CANCEL_PATH
);

use constant DEBUG => 1;

######################################################################

our $bad_cancel_hosts = {};
# our $bad_cancel_paths = {};

######################################################################
sub check_cancel_src($)
######################################################################
{
  my $r_src_hdr = shift || confess;

  if (exists( $r_src_hdr->{'NNTP-Posting-Host'} ))
  {
    my $host = $r_src_hdr->{'NNTP-Posting-Host'};
    if (exists( $bad_cancel_hosts->{ $host } ))
    {
      return (0, 'Cancel from bad NNTP-Posting-Host ' . $host);
    }
  }

  if (defined(SAFE_CANCEL_PATH) && defined( $r_src_hdr->{'Path'} ))
  {
    my $path = $r_src_hdr->{'Path'};
    if (exists( SAFE_CANCEL_PATH->{$path} ))
    {
      if (DEBUG > 1)
      {
	INN::syslog('N', "SAFE_CANCEL_PATH path=$path");
      }
      return (+1, undef);
    }
    elsif (DEBUG > 1)
    {
      INN::syslog('N', "not SAFE_CANCEL_PATH path=$path");
    }
  }

  return (0, undef);
}

######################################################################
# r_src_hdr ... reference to hash of headers of cancel/supersedes message
# target    ... message ID of target message
# descr     ... either 'Cancel' or 'Supersedes'
#
sub verify_cancel($$$;$)
######################################################################
{
  my $r_src_hdr = shift || confess;
  my $target = shift || confess;
  my $descr = shift || confess;
  my $is_local = shift || 0;

  if (DEBUG > 1)
  {
    INN::syslog('N',
      "verify_cancel target=$target descr=$descr is_local=$is_local");
  }

  my $target_hdr = INN::head($target);
  if (defined($target_hdr))
  {
    # Parse headers of target article, store fields in %target_hdr.
    # Continuation lines are ignored.
    my %target_hdr;
    for my $line(split(/\s*\n/, $target_hdr))
    {
      if ($line =~ m/^([[:alnum:]-]+):\s+(.*)/)
	{ $target_hdr{$1} = $2; }
    }

    my $lock = $target_hdr{'Cancel-Lock'};
    if (defined($lock))
    {
      my $key = $r_src_hdr->{'Cancel-Key'};
      unless(defined($key))
      {
	return (0, "$descr of $target without Cancel-Key");
      }
      my $rc = verify_cancel_key($key, $lock, $target);
      return (0, $descr . ': ' . $rc) if (defined($rc));

      # A this point we have a cancel authenticated through
      # a Cancel-Key matching a Cancel-Lock. This overrides
      # any negative decision check_cancel_src() might give.
    }
    else
    { #
      # Target is not protected by lock.
      #
      my ( $status, $msg ) = check_cancel_src($r_src_hdr);
      return ($status, $msg) if (defined($msg));

      if ($status <= 0)
      { #
        # Target is not authenticated by any means.
	#
	if ($is_local || CANCEL_ONLY_AUTHORIZED)
	{
	  return ($status, "Unauthorized $descr of $target");
	}
        # At this point target is not authenticated but continue.
      }
    }

    # If innd is started without option -C then INN::cancel is redundant.
    # However, with option -C the caller of verify_cancel can chose to
    # ignore the return value. In that case invalid cancel controls
    # and supersedes will not remove the target but still be present in
    # the news spool.
    
    if (DEBUG > 0)
    {
      INN::syslog('N', "INN::cancel target=$target descr=$descr");
    }
    INN::cancel($target);
  }
  else # if (defined($target_hdr))
  {
    #
    # Target not found in news spool.
    #
    my ( $status, $msg ) = check_cancel_src($r_src_hdr);
    return ($status, $msg) if (defined($msg));

    if (CANCEL_MISSING_TARGET &&
       (!CANCEL_ONLY_AUTHORIZED || $status > 0)
    )
    {
      if (DEBUG > 0)
      {
        INN::syslog('N', "INN::addhist target=$target descr=$descr");
      }
      INN::addhist($target);
    }
    else
    {
      return (0, "$descr of missing ID $target");
    }
  }

  return (0, undef);
}

######################################################################
sub check_local_path_id($)
######################################################################
# Some moderated groups leave header 'Injection-Info' intact.
# Consequently this function will return '1' for such posts.
######################################################################
{
  my $r_src_hdr = shift || confess;

  # Header "X-Trace" is set by INN 2.5.x or older. The first word
  # (separated by white-space) is the originating path ID.
  # Header "Injection-Info" is defined by RFC 5536 and set by INN
  # 2.6.x. The first word (separated by white space or semi-colon)
  # is the originating path ID.

  for my $field('X-Trace', 'Injection-Info')
  {
    my $value = $r_src_hdr->{'X-Trace'};
    if (defined($value) && $value =~ m/^\s*([^\s;]+)/)
    {
      if (exists(&LOCAL_PATH_ID()->{$1}))
      {
        INN::syslog('D', 'check_local_path_id=1 ' . $value);
	return 1;
      }
    }
  }
  return 0;
}

######################################################################
sub handle_cancel($$$)
######################################################################
{
  my $r_src_hdr = shift || confess;
  my $target = shift || confess;
  my $descr = shift || confess;

  # reject invalid cancel/supersede from our local users
  my $is_local = check_local_path_id($r_src_hdr);

  if (DEBUG > 1)
  {
    my $path = $r_src_hdr->{'Path'};
    $path = '' unless defined($path);
    INN::syslog('D',
      "handle_cancel target=$target descr=$descr is_local=$is_local path=$path");
  }
  my ( $status, $msg ) = verify_cancel($r_src_hdr, $target, $descr,
    $is_local);
  if (defined($msg))
  {
    my $group = $r_src_hdr->{'Newsgroups'};
    if (defined($group) && $group =~ m/^(?:$GROUPS_ACCEPTING_ANY_CANCEL)[^,]*/o)
    {
      INN::syslog('N', $msg . ' (override in $group)');
      return undef;
    }

    if (REJECT_INVALID_CANCEL || $status < 0 || $is_local)
    {
      INN::syslog('N', $msg . ' (rejected)');
      return $msg;
    }

    INN::syslog('N', $msg);
  }
  return undef;
}

######################################################################
1;
#####################################################################
