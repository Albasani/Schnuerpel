######################################################################
#
# $Id: AuthLDAP.pm 509 2011-07-20 13:55:30Z alba $
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
# See etc/auth for usage and configuration.
#
######################################################################
package Schnuerpel::INN::AuthLDAP;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &ldap_auth
  &ldap_init
);
use strict;

use Carp qw( confess );
use Net::LDAP();

use Schnuerpel::Config qw(
  &LDAP_HOST
  &LDAP_LOCALADDR
  &LDAP_SEARCH_BASE
);

######################################################################
# configuration
######################################################################

use constant DEBUG => 0;

######################################################################
# variables
######################################################################

my $ldap;

######################################################################
sub ldap_init()
######################################################################
{
  my $msg = 'ldap_init: ';

  $ldap = Net::LDAP->new(LDAP_HOST,
    timeout => 30,
    version => 3,
    onerror => undef,
    localaddr => LDAP_LOCALADDR
  );
  unless($ldap)
  {
    my $msg = 'Can\'t connect to LDAP server ' . LDAP_HOST . "\n" . $@;
    INN::syslog('E', $msg);
    return $msg;
  }

  return undef;
}

######################################################################
# Return value is ( $confidence, $nntp_code, $error_text )
# $confidence == +1 ... successful authentication
# $confidence ==  0 ... authentication failed, try next module
# $confidence == -1 ... authentication failed, abort
sub ldap_auth($;$$) 
######################################################################
{
  my $username = shift || die "No username";
  my $password = shift;
  my $hostname = shift;

  if (!defined($ldap))
  {
    my $msg = ldap_init();
    return ( 0, 403, $msg ) if (defined($msg));
  }

  my $msg = 'ldap_auth: ' . $username . ': ';
  my $userdn = 'uid=' . $username . ',' . LDAP_SEARCH_BASE;
  my $rc = $ldap->bind($userdn,
    password => $password,
    version => 3
  );

  if ($rc->code)
  {
    $msg .= "login failed";
    my $detail = $msg;
    if (DEBUG)
    {
      if (defined($password))
	{ $detail .= ', password=' . $password; }
      $detail .= ', userdn=' . $userdn;
    }
    $detail .= ', error=' . $rc->error_text();
    INN::syslog('E', $detail);
    return ( 0, 481, $msg );
  }

  $rc = $ldap->unbind();
  if ($rc->code)
  {
    INN::syslog('W', $msg . ' unbind failed, error=' . $rc->error_text());
  }

  $ldap->disconnect();
  undef $ldap;

  # this message is searched by onno-send-login.awk
  $msg = 'LDAP authenticated ' . $username;
  if ($hostname) { $msg .= ' ' . $hostname; }
  INN::syslog('N', $msg);

  $::authenticated{module} = 'LDAP';
  return ( +1, 281, undef );
}

######################################################################
1;
######################################################################
