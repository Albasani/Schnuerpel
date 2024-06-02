#!/usr/bin/perl -w
#
# $Id: send-article.pl 154 2008-12-18 19:38:00Z alba $
#
# Copyright 2008 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Opens NNTP connection, sets reader mode and logs in.
# Login credentials are hard coded. See below.
# Reads one article from stdin and sends it to the server.
#
######################################################################

use constant USERNAME => 'foo@bar.baz';
use constant PASSWORD => 'password';
use constant NNTPSERVER => localhost';
use constant NNTPPORT => 119;

use strict;
use Socket qw( &PF_INET &sockaddr_in &SOCK_STREAM );

my $sock;

#######################################################################
sub yield()
#######################################################################
{
  my $line;
  my $bytes_read = sysread($sock, $line, 0x1000) || die "sysread: $!";
  die "sysread: bytes_read=$bytes_read" if ($bytes_read <= 0);
  $line =~ s#\s+$##;
  print $line, "\n";
}

######################################################################
# MAIN
######################################################################

my $proto = getprotobyname('tcp') || die "getprotobyname: $!";
socket($sock, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";

my $iaddr = gethostbyname(NNTPSERVER) || die "gethostbyname: $!";
my $paddr = sockaddr_in(NNTPPORT, $iaddr) || die "sockaddr_in: $!";
connect($sock, $paddr) || die "connect: $!";

yield(); syswrite $sock, "MODE READER\r\n";
yield(); syswrite $sock, 'AUTHINFO USER ' . USERNAME . "\r\n";
yield(); syswrite $sock, 'AUTHINFO PASS ' . PASSWORD . "\r\n";
yield(); syswrite $sock, "POST\r\n";
yield();

while(<>)
{
  s#[\r\n]+$##; # remove line feed
  s#^\.#..#;    # escape lines starting with dot
  syswrite $sock, $_ . "\r\n";
}

syswrite $sock, ".\r\n"; yield();
syswrite $sock, "QUIT\r\n"; yield();

######################################################################
