######################################################################
#
# $Id: HashArticle.pm 609 2011-08-28 00:08:59Z alba $
#
# Copyright 2010-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Parse and manipulate a few special headers of Usenet posts. This
# module works with the hash of headers provided by INN to perl
# hooks (filter_innd.pl and filter_nnrpd.pl). See NewsArticle.pm for
# similar code that works on instance of News::Article
#
######################################################################

package Schnuerpel::HashArticle;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  get_posting_time_str
  get_pruned_path
  get_posting_timestamp
  make_xtrace
  parse_injection_info
  parse_x_trace
);

use strict;
use Carp qw( confess );
use POSIX qw();
use Date::Parse qw();

######################################################################
sub get_pruned_path($$)
######################################################################
# This function is used inside filter_nnrpd.pl, i.e. with posts
# submitted by local users that are not yet injected into Usenet.
#
# A typical value for "Path" at that points looks like this:
#   news.albasani.net!not-for-mail
# If "news.albasani.net" exists in $r_prune then '' is returned.
#
# If the user preloads "Path" then it can look like this:
#   news.albasani.net!path.preload.is.cool
# Or this:
#   news.albasani.net!path.preload.is.cool!not-for-mail
# In both cases 'path.preload.is.cool' is returned.
#
######################################################################
{
  my $path = shift;
  my $r_prune = shift;

  if (!$path) { return $path; }

  my $result = '';
  my $separator = '';
  for my $part( split(/!/, $path) )
  {
    if ($part ne 'not-for-mail' &&
        $part ne '.POSTED' &&
        !exists($r_prune->{$part})
    ){
      $result .= $separator;
      $result .= $part;
      $separator = '!';
    }
  }

  return $result;
}

###########################################################################
sub get_posting_timestamp($)
###########################################################################
{
  my $r_hdr = shift || confess 'No $r_hdr';

  my @error_msg;
  my @fields = ( 'NNTP-Posting-Date', 'Injection-Date', 'Date' );
  for my $field(@fields)
  {
    my $timestr = $r_hdr->{$field};
    if ($timestr)
    {
      # See <4E0C6972.123C.0030.1@boku.ac.at> for a date field that
      # includes the references header after a line feed.
      $timestr =~ s/^([^\r\n]+).*/$1/;

      my $t = Date::Parse::str2time($timestr);
      if (defined($t)) { return $t; }
      push @error_msg,
        sprintf("Can't parse time string (%s): %s", $field, $timestr);
    }
  }

  if ($#error_msg < 0)
  {
    push @error_msg,
      sprintf("None of %s defined.", join(', ', @fields));
  }
  my $msgid = $r_hdr->{'Message-ID'};
  if ($msgid) { push @error_msg, 'In message ' . $msgid; }
  die join("\n", @error_msg);
}

###########################################################################
sub make_xtrace($$)
###########################################################################
{
  my $r_hdr = shift || confess 'No r_hdr';
  my $encode = shift || confess 'No encode';
  my $info = $r_hdr->{'Injection-Info'} || confess 'No "Injection-Info" in $r_hdr';

  my $r = parse_injection_info($info);
  my $timestamp = get_posting_timestamp($r_hdr);

  return
    $r->{'path-id'} . ' ' .
    &$encode(sprintf('%u %u %s (%s)',
      $timestamp,
      $r->{'logging-data-pid'},
      $r->{'logging-data-host'},
      POSIX::strftime('%d %b %Y %H:%M:%S %Z', localtime($timestamp))
    ));
}

######################################################################
sub parse_x_trace($)
######################################################################
# Input:
#   Value of header 'X-Trace', as defined by INN 2.5.x or older
#   Example:
#     news.albasani.net 1283547501 21315 127.0.0.1 (3 Sep 2010 20:58:21 GMT)
# Output: Reference to hash
######################################################################
{
  my $x_trace = shift || confess;

  my @field = split(/\s+/, $x_trace);
  my %result =
  ( # these are standard fields defined by INN 2.5.x and older
    'path-id' => $field[0],
    'timestamp' => $field[1],		# seconds since 1970
    'pid' => $field[2],			# process ID of nnrpd
    'posting-host' => $field[3],	# IP address or host name
  );

  if ($x_trace =~ m/(.*)\s+([[:xdigit:]]+)$/)
  {
    # The cyclic redundancy check is a custom field.
    # It was added by old versions of Schnuerpel.
    $result{'crc32'} = $2;
    $x_trace = $1;
  }

  # The posting date is again defined by INN 2.5.x and older
  if ($x_trace =~ m/\(([^()]+)\)$/)
  {
    $result{'posting-date'} = $1;
  }

  return \%result;
}

######################################################################
sub parse_injection_info($)
######################################################################
# Input: Value of header 'Injection-Info', as defined by RFC 5536,
# section 3.2.8.
#
# Output: Reference to hash
######################################################################
{
  my $info = shift || confess;
  # note that Injection-Info contains line feeds

  $info =~ m/^\s*([^\s;]+)\s*;?(.*)/s || confess;
  my %result = ( 'path-id' => $1 );
  $info = $2;

  while($info =~ m/^\s*([\w_-]+)\s*=\s*(?:"([^"]+)"|(\S+))\s*;?(.*)/s)
  {
    $result{$1} = defined($2) ? $2 : $3;
    $info = $4;
  }

  my $ld = $result{'logging-data'};
  if (defined($ld))
  {
    # the original "logging-data" created by INN 2.6.x consists only
    # of the numeric process ID. Create an alias compatible with
    # Schnuerpel's enhanced version.
    if ($ld =~ /^\d+$/)
    {
      $result{'logging-data-pid'} = $ld;
    }
    else
    { # The ""logging-data" created by Schnuerpel consists of many parts.
      while($ld =~ m/^\s*([\w_-]+):(?:"([^"]+)"|(\S+))\s*(.*)/)
      {
	$result{'logging-data-' . $1} = defined($2) ? $2 : $3;
	$ld = $4;
      }
    }
  }

  my $ph = $result{'posting-host'};
  if (defined($ph) && !exists($result{'logging-data-host'}))
  {
    $result{'logging-data-host'} = $ph;
  }

  return \%result;
}

######################################################################
1;
######################################################################
