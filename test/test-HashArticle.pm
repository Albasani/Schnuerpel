#!/usr/bin/perl -w
######################################################################
#
# $Id: test-HashArticle.pm 543 2011-07-31 20:37:44Z alba $
#
# Copyright 2010-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
# Test suite for package Schnuerpel::HashArticle.
######################################################################
use strict;
use Carp qw( confess );
use Data::Dumper qw( Dumper );
use Schnuerpel::HashArticle qw(
  get_posting_timestamp
  parse_x_trace
  parse_injection_info
);

######################################################################

use constant R_HDR => {
  'Subject'	     => 'MAKE MONEY FAST!!', 
  'From'	     => 'Joe Spamer <him@example.com>',
  'Date'	     => '10 Sep 1996 15:32:28 UTC',
  'Newsgroups'     => 'alt.test',
  'Path'	     => 'news.example.com!not-for-mail',
  'Organization'   => 'Spammers Anonymous',
  'Lines'	     => '5',
  'Distribution'   => 'usa',
  'Message-ID'     => '<6.20232.842369548@example.com>',
  'Injection-Info' => 'news.example.com; posting-host="127.0.0.1"; logging-data="24671"; mail-complaints-to="abuse@example.com"',
  '__BODY__'	     => 'Send five dollars to the ISC, c/o ...',
  '__LINES__'	     => 5
};

######################################################################
sub test_string_array($$)
######################################################################
{
  my $func = shift || die;
  my $r_array = shift || die;

  for my $string( @$r_array )
  {
    my $r = &$func($string);
    print Dumper($r), "\n";
  }
}

######################################################################
sub test_parse()
######################################################################
{
  my $TRACE = [
    # a plain X-Trace header as created by INN 2.4.x
    'news.example.com 1284069406 3102 127.0.0.1 (9 Sep 2010 21:56:46 GMT)',

    # X-Trace header created by INN 2.4.x, CRC32 added by old version of Schnuerpel
    'news.example.com 1262736254 10631 127.0.0.1 (6 Jan 2010 00:04:14 GMT) 5e220d0b',
  ];

  my $INFO = [
    # a plain Injection-Info header as created by INN 2.6.2
    'news.example.com; posting-host="127.0.0.1"; logging-data="24671"; mail-complaints-to="abuse@example.com"',
    
    # a Injection-Info created by INN 2.6.2 and heavily modified by Schnuerpel
    'news.example.com; logging-data="pid:3102 crc:6036c429 host:78.46.73.112 uid:alexander.bartolich@gmx.at au:SQL"; mail-complaints-to="abuse@albasani.net"',
  ];

  test_string_array(\&parse_x_trace, $TRACE);
  test_string_array(\&parse_injection_info, $INFO);
}

######################################################################
sub test_time($)
######################################################################
{
  my $r_hdr = shift || confess;

  my $timestamp = eval { get_posting_timestamp($r_hdr); };
  if ($@) { warn $@; $timestamp = 0; }
  printf "get_posting_timestamp=%d\n", $timestamp;
  # my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
}

######################################################################
# MAIN
######################################################################
test_parse;

test_time({ 'Message-ID' => '<empty-hash>' });
{
  my $r = R_HDR;
  my %copy = %$r;
  delete $copy{'Date'};
  $copy{'Message-ID'} = '<copy-of-R_HDR>';
  test_time(\%copy);
}
test_time(R_HDR);
