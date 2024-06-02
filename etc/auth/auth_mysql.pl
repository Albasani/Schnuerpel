#!/usr/bin/perl -w
BEGIN { push(@INC, '/opt/schnuerpel/lib', '/opt/schnuerpel/etc'); }

use strict;
use Schnuerpel::INN::AuthSQL qw( sql_auth sql_init );

sub auth_init() { return sql_init(); }
sub authenticate()
{
  my @rc = sql_auth( $::attributes{username}, $::attributes{password} );
  shift(@rc); # discard confidence level
  return @rc;
}

1;
