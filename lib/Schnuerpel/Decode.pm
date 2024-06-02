######################################################################
#
# $Id: Decode.pm 655 2012-06-30 21:57:46Z root $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::Decode;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  decode_from_stream
  decode_headers
  decode_headers_from_stream
  print_cancel
  print_summary
);
use strict;

use Schnuerpel::Crypt qw(
  getCipher
);
use Schnuerpel::HashArticle qw(
  get_posting_timestamp
);
use Schnuerpel::INN::CancelLock();

use Carp qw( confess );
use Date::Parse();
use MIME::Base64();
use String::CRC32();

######################################################################

use constant DEBUG => 0;

######################################################################
sub string($$)
######################################################################
{
  my $cipher = shift || confess;
  my $string = shift;

  my $binary = MIME::Base64::decode_base64( $string );
  my $result = eval { $cipher->decrypt($binary); };
  if ($@) {
    warn '$cipher->decrypt(\'' . $string . '\') failed, ' . $@;
    return undef;
  }
  $result =~ s#^[^\n]*\n##;
  return $result;
}

######################################################################
sub stream($;$)
######################################################################
{
  my $file = shift;
  my $time = shift;

  my $cipher = getCipher($time);
  while(my $input = <$file>)
  {
    print string($cipher, $input), "\n";
  }
}

######################################################################
sub decode_xtrace($$$)
######################################################################
{
  my $r_result = shift || die;
  my $r_header = shift || die;
  my $cipher = shift || die;

  my $field = 'X-Trace';
  my $xtrace = $r_header->{$field};
  if (!$xtrace)
  {
    if (DEBUG) { warn "No $field"; }
    return;
  }
  if ($xtrace !~ m/^(\S+\s+)(.*)$/)
  {
    $r_header->{$field} = string($cipher, $xtrace);
    # printf "%s: %s\n", $field, string($cipher, $xtrace);
    return;
  }

  my $plain = string($cipher, $2);
  $r_header->{$field} = $1 . $plain;
  # printf "%s: %s%s\n", $field, $1, $plain;

  my @plain = split(/\s/, $plain);
  if ($#plain >= 8)
  {
    $r_result->{'crc32_from_Trace'} = hex($plain[8]);
  }
}

######################################################################
sub decode_injection_info($$$)
######################################################################
{
  my $r_result = shift || die;
  my $r_header = shift || die;
  my $cipher = shift || die;

  # Injection-Info is defined by INN 2.6.x.
  # See RFC 5536, section 3.2.8.
  my $info = $r_header->{'Injection-Info'};

  if (!defined($info))
  {
    if (DEBUG) { warn "No Injection-Info"; }
    return;
  }

  my %decoded_field;
  for my $field('logging-data', 'posting-account', 'posting-host')
  {
    my $decoded;

    # note that Injection-Info contains line feeds
    $info =~ s/
      ^(|.*;\s*)($field\s*=\s*")([^"]*)(".*)$
    / $1 . $2 . ($decoded = string($cipher, $3)) . $4
    /esx;

    if (defined($decoded)) { $decoded_field{$field} = $decoded; }
  }
  $r_header->{'Injection-Info'} = $info;

  if (exists( $decoded_field{'posting-account'} ))
  {
    $r_result->{'user_id'} = $decoded_field{'posting-account'};
  }

  my $data = $decoded_field{'logging-data'};
  if (defined($data))
  {
    if ($data =~ m/\bcrc:([[:xdigit:]]+)/)
      { $r_result->{'crc32_from_logging_data'} = hex($1); }

    if ($data =~ m/\buid:([[:xdigit:]]+)/)
      { $r_result->{'user_id'} = $1; }
  }
}

######################################################################
sub decode_headers($;$)
######################################################################
{
  my $r_header = shift || confess;
  my $timestamp = shift;

  my $id = $r_header->{'Message-ID'} || confess 'No Message-ID';

  if (!$timestamp)
  {
    $timestamp = eval { get_posting_timestamp($r_header); };
    if ($@) { warn $@; $timestamp = time(); }
  }
  my $cipher = getCipher($timestamp);

  for my $field('X-User-ID', 'X-NNTP-Posting-Host')
  {
    my $value = $r_header->{$field};
    if ($value)
    {
      $r_header->{$field} = string($cipher, $value) ||
        warn "Decoding field $field in message $id failed";
    }
    elsif (DEBUG)
    {
      warn "No $field in message $id";
    }
  }

  my $r_result =
  {
    'cipher' => $cipher,
    'header' => $r_header,
    # X-User-ID is a custom field set by old versions of
    # Schnuerpel::INN::Filter (befor Injection-Info came in fashion)
    'user_id' => $r_header->{'X-User-ID'}
  };

  decode_xtrace($r_result, $r_header, $cipher);
  decode_injection_info($r_result, $r_header, $cipher);

  my $user_id = $r_result->{'user_id'};
  if (defined($user_id))
  {
    # Second word of X-User-ID is authentication module, e.g. "SQL"
    # or "LDAP". Cancel-Key is calculated only from first word.
    $user_id =~ s/\s.*//;

    my $key = Schnuerpel::INN::CancelLock::calc_cancel_key(
      $user_id,
      $r_header->{'Message-ID'}
    );
    $r_result->{'cancel_key'} = 'sha1:' . $key;
  }

  return $r_result;
}

######################################################################
sub decode_headers_from_stream($;$)
######################################################################
{
  my $file = shift || die;
  my $time = shift;

  my %header;
  my $last_key;
  while(my $input = <$file>)
  {
    if ($input =~ /^([^\s:]+): *(.*)/)
    {
      # printf "[%s] = [%s]\n", $1, $2;
      $header{$last_key = $1} = $2;
      next;
    }
    if ($input =~ /^$/)
      { last; }

    if ($input =~ m/^\s*(\s.*)$/ && defined($last_key))
    {
      $header{$last_key} .= $1;
      next;
    }
    die "Invalid header line: " . $input;
  }

  return decode_headers(\%header, $time);
}

######################################################################
sub decode_from_stream($;$)
######################################################################
{
  my $file = shift || die;
  my $time = shift;

  my $r_posting = decode_headers_from_stream($file, $time);
  {
    local $/ = undef; my $body = <$file>;
    die "Posting has no body." unless(defined($body));
    $r_posting->{body} = $body;
    $r_posting->{crc32_from_body} = String::CRC32::crc32($body);
  }
  return $r_posting;
}

######################################################################
sub print_summary($)
######################################################################
{
  my $posting = shift || die;

  # NNTP-Posting-Host is defined by INN 2.5.x or older
  # X-Trace is defined by INN 2.5.x or older
  # X-User-ID is a custom header added by Schnuerpel::INN::Filter

  my $r_header = $posting->{header} || die;
  for my $field(
    'Injection-Info',
    'X-NNTP-Posting-Host',
    'X-Trace',
    'X-User-ID')
  {
    my $value = $r_header->{$field};
    if ($value) { printf "%s: %s\n", $field, $value; }
  }

  if (exists( $posting->{'cancel_key'} ))
  {
    printf "Cancel-Key: %s\n", $posting->{'cancel_key'};
  }

  my $crc32_from_body = $posting->{'crc32_from_body'} || die;
  for my $field('crc32_from_Trace', 'crc32_from_logging_data')
  {
    my $crc32 = $posting->{$field};
    if (defined($crc32))
    {
      printf "crc32(%x) %s\n",
	$crc32_from_body,
	($crc32_from_body == $crc32) ? 'OK' : 'FAILED';
    }
  }
}

######################################################################
sub print_cancel($)
######################################################################
{
  my $posting = shift || die;
  my $r_header = $posting->{header} || die;

  my $id = $r_header->{'Message-ID'} || die;
  $id =~ m/^<([^<>]+)>$/;
  my $core_id = $1;

  printf "Message-ID: <cancel.%s>\n", $core_id;
  printf "Newsgroups: %s\n", $r_header->{'Newsgroups'};
  printf "Cancel-Key: %s\n", $posting->{cancel_key};
  printf "Subject: cmsg cancel %s\n", $id;
  printf "Control: cancel %s\n", $id;
}

######################################################################
1;
######################################################################
