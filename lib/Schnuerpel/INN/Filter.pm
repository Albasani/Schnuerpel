######################################################################
#
# $Id: Filter.pm 627 2011-10-29 23:36:18Z alba $
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
# Used by INN's filter_nnrpd.pl
#
######################################################################

package Schnuerpel::INN::Filter;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  check_headers
  encrypt_headers
  get_local_approved_groups
);
use strict;

use Carp qw( confess );

use Schnuerpel::Config qw(
  $APPROVED_ALLOWED
  %CANCEL_USER
  &CLEAN_PATH
  %CLOAKED_USER
  %CONTROL_USER
  &CREATE_MISSING_X_TRACE
  &CROSSPOST_REQUIRES_FUP2
  %FORCE_FROM
  $INVALID_FROM
  $INVALID_REPLY_TO
  %MODERATOR_USER
  $NEWGROUP_ALLOWED
);
use Schnuerpel::Crypt qw(
  encode
);
use Schnuerpel::HashArticle qw(
  make_xtrace
);
use Schnuerpel::INN::ShellVars qw(
  get_group_status
);

use String::CRC32 qw(
  crc32
);

use constant DEBUG => 1;

###########################################################################
sub control_allowed($$$)
###########################################################################
{
  my $user = shift || confess;
  my $control = shift || confess;
  my $approved_allowed = shift || confess;

  # cancels are not restricted, yet
  if ($control =~ m/^cancel\s+/i)
  {
    if (exists( $CANCEL_USER{$user} ))
    {
      $$approved_allowed = 1;
    }
    return undef;
  }

  if ($control !~ m/^(newgroup|rmgroup|checkgroups)\s+(.+)/i)
    { return "Invalid control $control"; }
  my $command = $1;
  my $group = $2;
  INN::syslog('notice', "control=$control command=$command group=$group");

  if ($command eq 'newgroup' && $group =~ m/^(?:$NEWGROUP_ALLOWED)[^,]*/o)
  {
    $$approved_allowed = 1;
    return undef;
  }

  if (exists( $CONTROL_USER{$user} ))
  {
    my $pattern = $CONTROL_USER{$user};
    if ($pattern && $group !~ m/$pattern/)
    {
      return "You are allowed to send $command to \"$pattern\" " .
        "but \"$group\" does not match.";
    }
    $$approved_allowed = 1;
    return undef;
  }

  return "You are not allowed to send $command ($group).";
}

###########################################################################
sub check_crosspost($$)
###########################################################################
{
  my $user = shift || confess 'No $user';
  my $r_hdr = shift || confess 'No $r_hdr';

  if (exists( $r_hdr->{'Control'} ))
  {
    # cancels are excempt from crossposting restrictions
    return undef if ($r_hdr->{'Control'} =~ m/^cancel\s+/i);
  }

  if (exists( $r_hdr->{'Approved'} ))
  {
    # approved postings are excempt from crossposting restrictions
    return undef;
  }

  my $newsgroups = $r_hdr->{'Newsgroups'};
  return 'Newsgroups: is required' unless(defined($newsgroups));

  my @newsgroups = split(/\s*,+\s*/, $newsgroups);
  my %hierarchy;
  my $nr_groups = map
    { $hierarchy{$1} = undef if (m/^([^.]+)\./); } @newsgroups;

  my $fup2;
  my $fup2_comma = 0;

  if (exists( $r_hdr->{'Followup-To'} ))
  {
    $fup2 = $r_hdr->{'Followup-To'};
    $fup2_comma = $fup2 =~ m/,/;
  }

  my $pattern = '(?:^|,)\s*(?:' . CROSSPOST_REQUIRES_FUP2 . ')';
  return undef unless(
    ($newsgroups =~ $pattern)
    ? $nr_groups > 1 || $fup2_comma
    : defined($fup2) && $fup2 =~ $pattern && $fup2_comma
  );

  unless(defined($fup2))
  {
    return 'Followup-To: is required for ' . $newsgroups;
  }
  if ($fup2_comma)
  {
    return "Followup-To: must specify exactly one group ($fup2)";
  }

  return undef;
}

###########################################################################
sub approved_allowed($$)
###########################################################################
{
  my $user = shift || confess 'No $user';
  my $newsgroups = shift || confess 'No $newsgroups';

  return undef if ($newsgroups =~ m/^(?:$APPROVED_ALLOWED)$/o);
    
  my $pattern = $MODERATOR_USER{$user};
  if (defined($pattern))
  {
    return undef if ($newsgroups =~ m/$pattern/);
    INN::syslog('debug', "MODERATOR_USER user=$user newsgroups=$newsgroups pattern=$pattern");
  }
  else
  {
    INN::syslog('debug', "MODERATOR_USER user=$user newsgroups=$newsgroups");
  }
  return 'You are not allowed to send approved postings to this group.';
}

###########################################################################
sub check_headers($$)
###########################################################################
{
  my $user = shift || confess 'No $user';
  my $r_hdr = shift || confess 'No $r_hdr';

  my $from = $r_hdr->{'From'};

  if (exists( $FORCE_FROM{$user} ))
  {
    my $from = $FORCE_FROM{$user};
    unless($from =~ m/$from/)
    {
      return "Your From header must match the string $from";
    }
  }

  if ($INVALID_FROM)
  {
    if ($from =~ m/$INVALID_FROM/o)
    {
      return 'Your from-header contains an invalid address.';
    }
  }

  if ($INVALID_REPLY_TO)
  {
    my $reply = $r_hdr->{'Reply-To'};
    if (defined($reply) && $reply =~ m/$INVALID_REPLY_TO/o)
    {
      return 'Your Reply-To header contains an invalid address.';
    }
  }

  my $approved_allowed = 0;
  if (exists( $r_hdr->{'Control'} ))
  {
    if (exists( $r_hdr->{'Supersedes'} ))
    {
      return 'You cannot have both Supersedes and Control.';
    }

    my $msg = control_allowed(
      $user, $r_hdr->{'Control'}, \$approved_allowed
    );
    return $msg if (defined($msg));
  }

  if (!$approved_allowed && exists( $r_hdr->{'Approved'} ))
  {
    my $msg = approved_allowed($user, $r_hdr->{'Newsgroups'});
    return $msg if (defined($msg));
  }

  return check_crosspost($user, $r_hdr);
}

###########################################################################
sub make_logging_data($$$;$)
###########################################################################
{
  my $user = shift;
  my $body = shift;
  my $posting_host = shift;
  my $pid = shift;

  # man perlvar
  # $$ ... The process number of the Perl running this script.
  if (!defined($pid)) { $pid = $$; }

  my $str = sprintf('pid:%s crc:%x host:%s uid:%s',
    $pid,
    crc32($body),
    $posting_host ? $posting_host : '',
    $user
  );

  my $module = $::authenticated{module};
  if (defined($module) && $module =~ /([^:]+)$/)
    { $str .= ' au:' . $1; }

  return encode($str);
}

###########################################################################
sub cloak_user($)
###########################################################################
{
  my $r_hdr = shift || confess 'No r_hdr';

  # "delete $r_hdr->{$f}" does not work, it is simply ignored
  for my $h(
    'Injection-Info',
    'NNTP-Posting-Host',
    'X-Complaints-To',
    'X-Trace'
  ){
    if (exists( $r_hdr->{$h} )) { $r_hdr->{$h} = ''; }
  }
}

###########################################################################
sub clean_path_header($;$)
###########################################################################
{
  my $r_hdr = shift || confess 'No r_hdr';
  my $mode = shift;

  if (!exists( $r_hdr->{'Path'} )) { return undef; }

  # With INN 2.6.x a typical Path at this point looks like this:
  # four.albasani.net!.POSTED.127.0.0.1!not-for-mail

  if (!defined($mode))
  {
    $r_hdr->{'Path'} =~ m/!\.POSTED\.([^!]*)/;
    return $1;
  }
  elsif ($mode eq '1036')
  {
    $r_hdr->{'Path'} =~ s/!\.POSTED\.([^!]*)//;
    return $1;
  }
  elsif ($mode eq '5537loose')
  {
    $r_hdr->{'Path'} =~ s/(!\.POSTED)\.([^!]*)/$1/;
    return $2;
  }
  else
  {
    confess "clean_path_header called with invalid mode '$mode'";
  }
}

###########################################################################
sub encrypt_headers_1036($$$)
###########################################################################
# INN 2.5.x and older complies to RFC 1036. It does not set a "Path"
# diagnostic but defines "NNTP-Posting-Host".
#
# Header "Injection-Info" is defined by INN 2.6.x. See RFC 5536, section
# 3.2.8. For posts to unmoderated groups we build something compatible.
#
# Submissions to moderated groups are forwarded to the moderator by email.
# These submissions are not allowed to have a header "Injection-Info".
###########################################################################
{
  my $user = shift || confess 'No user';
  my $r_hdr = shift || confess 'No r_hdr';
  my $r_body = shift || confess 'No r_body';

  my $info = '';
  my $status = get_group_status( $r_hdr->{'Newsgroups'} );

  # X-Trace is defined by INN 2.5.x or older. Flag "O originator" of
  # /etc/news/newsfeeds matches against the first word of X-Trace, so
  # keep that intact.
  if (exists( $r_hdr->{'X-Trace'} ))
  {
    if ($r_hdr->{'X-Trace'} =~ m/^(\S+)\s+(.*)/)
    {
      $info .= $1; # first word is news server name (or domain)
      $r_hdr->{'X-Trace'} = $1 . ' ' . encode($2);
    }
  }

  # NNTP-Posting-Host is optional but has a defined value
  # See RFC2980, section 3.4.1
  # NNTP-Posting-Host is defined by INN 2.5.x or older.
  my $posting_host = $r_hdr->{'NNTP-Posting-Host'};
  if (defined($posting_host))
  {
    $r_hdr->{'NNTP-Posting-Host'} = ($status eq 'm')
    ? encode($posting_host)
    : '';
  }

  $info .=
    '; logging-data="' .
    make_logging_data($user, $$r_body, $posting_host)
    . '"';

  if (exists( $r_hdr->{'X-Complaints-To'} ))
  {
    $info .= '; mail-complaints-to="' . $r_hdr->{'X-Complaints-To'} . '"';
    if ($status ne 'm') { $r_hdr->{'X-Complaints-To'} = ''; }
  }

  if ($status ne 'm')
  {
    # Header "Injection-Info" is defined by INN 2.6.x. See RFC 5536,
    # section 3.2.8. We build something compatible.
    $r_hdr->{'Injection-Info'} = $info;
  }
}

###########################################################################
sub encrypt_headers_5537($$$)
###########################################################################
# INN 2.6.x complies to RFC 5537 which defines a "Path" diagnostic and
# "Injection-Info".
###########################################################################
{
  my $user = shift || confess 'No user';
  my $r_hdr = shift || confess 'No r_hdr';
  my $r_body = shift || confess 'No r_body';

  my $posting_host = clean_path_header($r_hdr, CLEAN_PATH);

  # note that Injection-Info contains line feeds
  my $info = $r_hdr->{'Injection-Info'};

  # remove posting host, but store value in $1
  $info =~ s/;?\s*posting-host\s*=\s*"([^"]*)"\s*//s;

  if (DEBUG && defined($posting_host) && defined($1))
  {
    if ($posting_host ne $1)
    {
      INN::syslog('warn',
	"Host name mismatch; Path=$posting_host, Injection-Info=$1");
    }
  }

  $info =~ s/
    ^(|.*;\s*)(logging-data\s*=\s*")([^"]*)(".*)$
  / $1 . $2 . make_logging_data($user, $r_body, $posting_host, $3) . $4
  /esx;

  $r_hdr->{'Injection-Info'} = $info;

}

###########################################################################
sub encrypt_headers($$$)
###########################################################################
{
  my $user = shift || confess 'No user';
  my $r_hdr = shift || confess 'No r_hdr';
  my $r_body = shift || confess 'No r_body';
  ref($r_hdr) eq 'HASH' || confess 'r_hdr is not a hash reference';

  if (exists( $CLOAKED_USER{$user} ))
  {
    clean_path_header($r_hdr, '1036');
    cloak_user($r_hdr);
  }
  elsif (exists( $r_hdr->{'Injection-Info'} ))
  {
    if (&CREATE_MISSING_X_TRACE() && !exists($r_hdr->{'X-Trace'}))
    {
      $r_hdr->{'X-Trace'} = make_xtrace($r_hdr, \&encode);
    }
    encrypt_headers_5537($user, $r_hdr, $r_body);
  }
  else
  {
    encrypt_headers_1036($user, $r_hdr, $r_body);
  }
}

###########################################################################
sub get_local_approved_groups()
###########################################################################
# Converts values from Schnuerpel's Config.pm to a setting suitable for
# Cleanfeed.
###########################################################################
{
  my %group;
  for my $part(split(/\|/, $APPROVED_ALLOWED))
  {
    $group{$part} = undef;
  }
  while(my ($user, $pattern) = each %MODERATOR_USER)
  {
    for my $part(split(/[(),?:|^]+/, $pattern))
    {
      if (!$part) { next; }
      $group{$part} = undef;
    }
  }

  my $result = join('|', sort(keys(%group)));
  return $result;
}

######################################################################
1;
######################################################################
