######################################################################
#
# $Id: Crypt.pm 538 2011-07-28 02:36:41Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::Crypt;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  encode
  getCipher
  getKey
  printNewKey
  resetCipher
);

use strict;
use Carp qw( confess );
# use Data::Dumper qw( Dumper );

use Schnuerpel::Config qw(
  &KEY
  &KEYSIZE
);
use Schnuerpel::RandPasswd qw( chars );

use Date::Parse();
use Crypt::Rijndael();
use MIME::Base64();

use constant DEBUG => 0;
use constant MIN_PADDING => 6;

my $last_cipher;
my $last_key;

######################################################################
sub printNewKey()
######################################################################
{
  my $key = chars(KEYSIZE, KEYSIZE);
  $key =~ y#'\\#ab#;

  my $t = time();
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
  = localtime($t);

  printf "  # since %04d-%02d-%02d %02d:%02d:%02d\n",
    $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
  printf "  [ %d, '%s' ],\n", $t, $key;
}

######################################################################
sub getKey(;$)
######################################################################
# One, optional argument: $time
# - If $time is not defined then the most recent key is returned.
# - If $time contains a non-digit character then it is converted
#   to an integer with Date::Parse::str2time.
# - Otherwise $time is assumed to a time value, i.e. seconds since
#   epoch.
######################################################################
{
  my $time = shift;
  
  if (!defined($time)) { return (KEY)[0]->[1]; }
  if ($time =~ /\D/)
  {
    my $t = Date::Parse::str2time($time);
    unless(defined($t))
    {
      die "E: Can't parse time string $time";
    }
    if (DEBUG)
    {
      my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday,
	$isdst) = localtime($t);
      printf "D: str2time %s = %d = %04d-%02d-%02d %02d:%02d:%02d\n",
	$time, $t, 1900 + $year, 1 + $mon, $mday, $hour, $min, $sec;
    }
    $time = $t;
  }

  for my $r(KEY)
  {
    unless(length($r->[1]) == KEYSIZE)
    {
      confess "KEYSIZE=" . KEYSIZE . " ref($r)=" . ref($r);
    }
    if ($time >= $r->[0])
    {
      if (DEBUG)
      {
	printf("D: getKey %d = [%s]\n", $time, $r->[1]);
      }
      return $r->[1];
    }
  }
}

######################################################################
sub resetCipher()
######################################################################
{
  $last_cipher = undef;
}

######################################################################
sub getCipher(;$)
# One, optional argument: $time
# Can be undefined, a date string, or a time value.  See getKey.
######################################################################
{
  my $time = shift;
  my $key = getKey($time) || confess "getKey failed";

  #
  # Note that Crypt::Rijndael on FC6 x86_64 (64 bits)
  # is not compatible to the 32-bit version. The 64-bit
  # code cannot decode output of the 32-code, and vice
  # versa.
  #
  unless(defined($last_cipher) && $last_key eq $key)
  {
    $last_cipher = new Crypt::Rijndael($key, Crypt::Rijndael::MODE_CBC);
    unless(defined($last_cipher))
    {
      $last_key = undef;
      die "Can't create instance of Crypt::Rijndael";
    }
    $last_key = $key;
  }
  return $last_cipher;
}

######################################################################
sub encode($;$)
######################################################################
{
  my $line = shift || confess;
  my $time = shift;

  # add one for line feed
  my $l = 1 + length($line);
  my $keysize = KEYSIZE;

  # round up to next multiple of KEYSIZE, which must be a power of two
  # MIN_PADDING is some integer greater 0
  my $padding = (($l + MIN_PADDING + $keysize) & ~($keysize - 1)) - $l;

  my $p = chars($padding, $padding);
  return MIME::Base64::encode_base64(
    getCipher($time)->encrypt($p . "\n" . $line),
    ''
  );
}

######################################################################
1;
######################################################################
