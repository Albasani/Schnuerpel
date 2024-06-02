#!/usr/bin/perl -w
#
# $Id: send-queue.pl 247 2009-12-28 00:19:06Z alba $
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
# Reads username and password from newsreader configuration.
# Opens NNTP connection, sets reader mode and logs in.
# Reads NNTP from stdin and sends it to the server.
#
######################################################################

use strict;
use Schnuerpel::ConfigNNTP qw( &VERBOSE );
use Socket qw(
  &PF_INET
  &sockaddr_in
  &SOCK_STREAM
);

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

#######################################################################
sub stream_article()
#######################################################################
{
  syswrite $sock, "POST\r\n"; yield();

  do
  {
    s#[\r\n]+$##;
    syswrite $sock, $_ . "\r\n";
  } while(<>);

  syswrite $sock, ".\r\n"; yield();
}

#######################################################################
sub stream_queue()
#######################################################################
{
  do
  {
    s#[\r\n]+$##;

    next if (m/^(AUTHINFO|MODE)\b/);
    return if (/^QUIT\b/);

    # printf "%s\r\n", $_;
    syswrite $sock, $_ . "\r\n";
    yield() if (/^\.$/);
  } while(<>);
}

######################################################################
# MAIN
######################################################################

my $config = Schnuerpel::ConfigNNTP->new();
my ( $host, $port ) = $config->get_host();
my ( $username, $password ) = $config->read_authinfo($host);

my $proto = getprotobyname('tcp') || die "getprotobyname: $!";
socket($sock, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";

my $iaddr = gethostbyname($host) || die "gethostbyname: $!";
my $paddr = sockaddr_in($port, $iaddr) || die "sockaddr_in: $!";
connect($sock, $paddr) || die "connect: $!";

yield(); syswrite $sock, "MODE READER\r\n";
yield(); syswrite $sock, "AUTHINFO USER $username\r\n";
yield(); syswrite $sock, "AUTHINFO PASS $password\r\n";
yield();

$_ = <> || exit 0;

if (m/^Newsgroups:\s/)
{
  stream_article();
}
else
{
  stream_queue();
}

syswrite $sock, "QUIT\r\n"; yield();

######################################################################
