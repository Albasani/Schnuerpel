######################################################################
#
# $Id: RandPasswd.pm 286 2010-02-24 02:28:02Z alba $
#
# Copyright 2009-2010 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Functions rand_int_in_range, random_chars_in_range and chars are
# compatible to package Crypt-RandPasswd by John Douglas Porter.
#
######################################################################

package Schnuerpel::RandPasswd;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  chars
);

use strict;
use Carp qw( confess );

######################################################################
sub rand_int_in_range($$)
######################################################################
{
  my ($min, $max) = @_;
  return $min + int(rand($max - $min + 1));
}

######################################################################
sub random_chars_in_range($$$$)
######################################################################
{
  my ($minlen, $maxlen, $lo_char, $hi_char) = @_;

  if ($minlen < 0)
    { confess "minlen $minlen is less than 0"; }
  if ($minlen > $maxlen)
    { confess "minlen $minlen is greater than maxlen $maxlen"; }

  my $len = rand_int_in_range($minlen, $maxlen);
  my $result = '';
  while(length($result) < $len)
  {
    $result .= chr(rand_int_in_range(ord($lo_char), ord($hi_char)));
  }
  return $result;
}

######################################################################
sub chars($$)
######################################################################
{
  my ($minlen, $maxlen) = @_;
  return random_chars_in_range($minlen, $maxlen, '!', '~');
}

######################################################################
1;
######################################################################
