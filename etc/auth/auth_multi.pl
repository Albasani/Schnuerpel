#!/usr/bin/perl -w
BEGIN { push(@INC, '/opt/schnuerpel/lib', '/opt/schnuerpel/etc'); }

use strict;
use Schnuerpel::INN::AuthSQL qw( sql_auth sql_init );
use Schnuerpel::INN::AuthLDAP qw( ldap_auth ldap_init );

sub auth_init() { return sql_init(); }
sub authenticate()
{
  my @rc_log;
  my @rc;
  for my $fn( \&sql_auth, \&ldap_auth )
  {
    @rc = &$fn(
      $::attributes{username},
      $::attributes{password},
      $::attributes{hostname}
    );
    push @rc_log, [ @rc ]; # add a copy of @rc to @rc_log
    last if ($rc[0] != 0);
  }
  if ($rc[0] <= 0)
  { # we return non-positive result, log all return codes
    for my $r(@rc_log) { INN::syslog('N', join(', ', @$r)); }
  }
  return ( $rc[1], $rc[2] );
}

1;
