######################################################################
#
# $Id: CancelLock.pm 618 2011-09-28 09:53:32Z alba $
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
# Used by both filter_nnrpd.pl and filter_innd.pl
# INN::syslog is defined by INN for both files.
# INN::head is available only to filter_innd.pl.
# Thus "verify_cancel" can be called only from there.
#
# See also:
#   more /usr/lib/news/doc/hook-perl
#   zless /usr/share/doc/inn2/hook-perl.gz
#
######################################################################

package Schnuerpel::INN::CancelLock;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  add_cancel_item
  calc_cancel_key
  add_cancel_lock
  verify_cancel_key
);
use strict;

use Schnuerpel::Config qw(
  &CANCEL_LOCK
  %CLOAKED_USER
);

use Carp qw( confess );
use MIME::Base64();
use Digest::SHA1();
use Digest::HMAC_SHA1();

######################################################################
sub add_cancel_item($$$)
######################################################################
{
  my ( $r_hdr, $name, $value ) = @_;
  my $prefix = $r_hdr->{$name};
  $prefix = defined($prefix) ? $prefix . ' sha1:' : 'sha1:';
  $r_hdr->{$name} = $prefix . $value;
}

######################################################################
sub calc_cancel_key($$)
######################################################################
{
  my $user = shift || confess "No user";
  my $message_id = shift || confess "No message_id";
  return MIME::Base64::encode(
    Digest::HMAC_SHA1::hmac_sha1($message_id, $user . CANCEL_LOCK), ''
  );
}

######################################################################
sub add_cancel_lock($$)
######################################################################
{
  my $user = shift || die;
  my $r_hdr = shift || die;

  if (exists( $CLOAKED_USER{$user} )) { return; }
  my $key = calc_cancel_key($user, $r_hdr->{'Message-ID'});
  my $lock = MIME::Base64::encode(Digest::SHA1::sha1($key), '');
  add_cancel_item($r_hdr, 'Cancel-Lock', $lock);

  return $key;
}

##############################################################################
sub verify_cancel_key($$$)
##############################################################################
{
  my $cancel_key = shift || confess;
  my $cancel_lock = shift || confess;
  my $target = shift || confess;

  my @msg;

  # INN::syslog('debug', "verify_cancel_key target=$target");

  my %lock;
  for my $l(split(/\s+/, $cancel_lock))
  {
    next unless($l =~ m/^(sha1|md5):(\S+)/);
    $lock{$2} = $1;
  }

  for my $k(split(/\s+/, $cancel_key))
  {
    unless($k =~ m/^(sha1|md5):(\S+)/)
    {
      push @msg, "Invalid Cancel-Key syntax '$k' for $target";
      next;  
    }

    my $key;
    if ($1 eq 'sha1')
      { $key = Digest::SHA1::sha1($2); }
    elsif ($1 eq 'md5')
      { $key = Digest::MD5::md5($2); }
    $key = MIME::Base64::encode_base64($key, '');

    if (exists($lock{$key}))
    {
      # INN::syslog('debug', "Valid Cancel-Key $key found for $target");
      return undef;
    }
  }

  push @msg, "No Cancel-Key matches Cancel-Lock of $target";
  return join("\n", @msg);
}


######################################################################
1;
######################################################################
