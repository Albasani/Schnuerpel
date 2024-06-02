#!/usr/bin/perl -sw
######################################################################
#
# $Id: update-host-list.pl 278 2010-02-10 12:11:38Z alba $
#
# Copyright 2010 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
use strict;
use Carp qw( confess );
# use Data::Dumper;

use DBI();

# use lib $ENV{'SCHNUERPEL_VAR'};
# use HostList;

use Schnuerpel::Config qw(
  &DB_DATABASE
  &DB_USER
  &DB_PASSWD
);

######################################################################
# configuration
######################################################################

use constant DEBUG => 0;

use constant HOST_TYPE_LOCAL => 1;
use constant HOST_TYPE_TOR => 2;

use constant SQL_SELECT_TYPE =>
  "SELECT id".
  "\nFROM r_host_ip_setup" .
  "\nWHERE name = ?";
use constant SQL_INSERT =>
  "INSERT INTO r_host_ip(ip, type, updated)" .
  "\nVALUES(?, ?, ?)" .
  "\nON DUPLICATE KEY UPDATE" .
  "\nupdated = ?";
use constant SQL_DELETE_OLD =>
  "DELETE FROM r_host_ip" .
  "\nWHERE updated < UNIX_TIMESTAMP() - 60*60*24*7";

######################################################################
sub connect_db()
######################################################################
{
  my $msg = 'sql_init: ';

  unless(defined(DB_DATABASE))
  {
    die 'Internal error, DB_DATABASE not configured.';
  }

  my $dbc = DBI->connect(DB_DATABASE, DB_USER, DB_PASSWD,
    { PrintError => 0, AutoCommit => 1 });
  return $dbc if (defined( $dbc ));

  die "DBI->connect failed.\n" . $DBI::errstr;
}

######################################################################
sub get_type_nr($$)
######################################################################
{
  my $dbc = shift || confess;
  my $type_name = shift || confess;

  my @row_ary  = $dbc->selectrow_array(SQL_SELECT_TYPE, undef, $::TYPE) ||
    die $dbc->errstr;
  if ($#row_ary != 0)
  {
    die "Type name $::TYPE not found in table r_host_ip_setup";
  }
  return 0 + $row_ary[0];
}

######################################################################
# main
######################################################################

my $now = time();
die 'Parameter TYPE missing' unless defined($::TYPE);

my $dbc = connect_db();
my $type_nr = get_type_nr($dbc, $::TYPE);
my $sth_insert = $dbc->prepare(SQL_INSERT) || die $DBI::errstr;

my %ip;
while(<>)
{
  next if (m/^#/);
  s/\s*$//;
  $ip{$_} = undef;
}

printf "package HostList::%s;\n", $::TYPE;
print  'require Exporter;', "\n";
print  '@ISA = qw(Exporter);', "\n";
print  '@EXPORT_OK = qw( &UPDATE &IP );', "\n";
print  "\n";
print  'use strict;', "\n";
print  "\n";
print  'use constant UPDATE => ', $now, ";\n";
print  'use constant IP =>', "\n";
print  '{', "\n";

for my $ip(sort(keys(%ip)))
{
  $sth_insert->execute($ip, $type_nr, $now, $now) ||
    die $sth_insert->errstr;
  printf "  '%s' => undef,\n", $ip;
}

print "};\n1;\n";

$dbc->do(SQL_DELETE_OLD) || die $DBI::errstr;

######################################################################
