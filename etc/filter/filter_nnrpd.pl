#!/usr/bin/perl -w
#
# $Id: filter_nnrpd.pl 388 2010-09-14 21:53:35Z alba $
#
# This is example code released to public domain.
# It is ment as an replacement for INN's
#   /etc/news/filter/filter_nnrpd.pl 
# Read comments below for instructions.
#
######################################################################

#
# You propably will have to change these directories 
#
BEGIN { push(@INC, '/opt/schnuerpel/lib', '/opt/schnuerpel/etc'); }

use Schnuerpel::INN::AuthSQL qw(
  sql_record
);

use Schnuerpel::INN::Filter qw(
  check_headers
  encrypt_headers
);

use Schnuerpel::INN::CancelLock qw(
  add_cancel_lock
  add_cancel_item
  calc_cancel_key
);

###########################################################################
sub filter_post
###########################################################################
{
  my $msg = check_headers($user, \%hdr);
  return $msg if (defined($msg));
  
  encrypt_headers($user, \%hdr, \$body);
  my $key = add_cancel_lock($user, \%hdr);
  sql_record(\%hdr, $key);
  sql_disconnect();

  if (exists( $hdr{'Control'} ) &&
    $hdr{'Control'} =~ m/^cancel\s+(<[^>]+>)/i)
  {
    my $key = calc_cancel_key($user, $1);
    add_cancel_item(\%hdr, 'Cancel-Key', $key);
  }
  elsif (exists( $hdr{'Supersedes'} ))
  {
    my $key = calc_cancel_key($user, $hdr{'Supersedes'});
    add_cancel_item(\%hdr, 'Cancel-Key', $key);
  }

  $modify_headers = 1;
  return '';
}

###########################################################################
