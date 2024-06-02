#!/usr/bin/perl -w
#
# $Id: test-filter-innd.pl 483 2011-03-05 22:09:32Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Find filter script as defined by INN configuration, load it,
# setup data structures with a test posting and simulate a call
# to filter functions by INN.
#
# Possible command line arguments:
#   startup_innd, filter_innd, filter_nnrpd
#
# Default if no argument given is 'filter_nnrpd'.
#
# Fedora: less /usr/lib/news/doc/hook-perl
# Debian: zless /usr/share/doc/inn2/hook-perl.gz 
#
######################################################################

use strict;
use Data::Dumper qw( Dumper );
use Schnuerpel::INN::ShellVars qw( load_innshellvars );
use Schnuerpel::INN::TestFilter qw( test_script );
use Schnuerpel::INN::Filter qw( get_local_approved_groups );

use constant FUNC_TEST =>
[
  [ 'filter_before_reload', sub {} ],
  [ 'filter_after_reload', sub {} ],
  [ 'filter_messageid()', \&test_setup_mid ],
  [ 'filter_art',
    \&Schnuerpel::INN::TestFilter::test_setup_hdr,
    \&Schnuerpel::INN::TestFilter::test_print_hdr
  ],
  [ 'filter_mode', \&Schnuerpel::INN::TestFilter::test_setup_mode ],
  [ 'filter_post',
    \&Schnuerpel::INN::TestFilter::test_setup_post,
    \&Schnuerpel::INN::TestFilter::test_print_post,
  ],
];

######################################################################
# MAIN
######################################################################

if ($#ARGV < 0)
{
  print "First argument must be name of configuration variable.\n";
  print "Supported values:\n";
  print "  startup_innd\n";
  print "  filter_innd\n";
  print "  filter_nnrpd\n";
  exit 0;
}

# Note that this changes $ENV{'HOME'}
load_innshellvars();

printf "\@INC=\n  %s\n", join("\n  ", @INC);

printf '$pathfilter=%s' . "\n", $inn::pathfilter;
unless(-d $inn::pathfilter)
{
  die "Directory $inn::pathfilter does not exist.";
}

printf 'get_local_approved_groups()=%s' . "\n",
  get_local_approved_groups();

for my $arg(@ARGV)
{
  my $var_name = 'inn::perl_' . $arg;

  no strict 'refs';
  my $script = ${ $var_name };
  use strict 'refs';

  unless(defined($script))
    { die "Variable $var_name is not defined."; }

  test_script $script, (FUNC_TEST);
}

######################################################################
package Schnuerpel::INN::TestFilter;
######################################################################

our %hdr;
our $body;
our $user;
our $modify_headers;

######################################################################
sub test_setup_hdr()
######################################################################
{
  %hdr = (
    'Subject'	     => 'MAKE MONEY FAST!!', 
    'From'	     => 'Joe Spamer <him@example.com>',
    'Date'	     => '10 Sep 1996 15:32:28 UTC',
    'Newsgroups'     => 'alt.test,alt.flame',
    'Followup-To'    => 'alt.flame,alt.test',
    'Path'	     => 'news.example.com!.POSTED.127.0.0.1!not-for-mail',
    'Organization'   => 'Spammers Anonymous',
    'Lines'	     => '5',
    'Distribution'   => 'usa',
    'Message-ID'     => '<6.20232.842369548@example.com>',
    'Injection-Info' => 'news.example.com; posting-host="127.0.0.1"; logging-data="24671"; mail-complaints-to="abuse@example.com"',
    '__BODY__'	     => 'Send five dollars to the ISC, c/o ...',
    '__LINES__'	     => 5

# Enable to test INVALID_REPLY_TO:
#   'Reply-To'     => 'alexander.bartolich@gmx.at.invalid',
  );
  return; # leave no value
}

######################################################################
sub test_print_hdr()
######################################################################
{
  print Data::Dumper::Dumper( \%hdr );
}

######################################################################
sub test_setup_mid()
######################################################################
{
  undef %hdr;
  return '<6.20232.842369548@example.com>';
}

######################################################################
sub test_setup_mode()
######################################################################
{
  # possible modes are throttled, paused, and running
  our %mode = (
    'Mode' => 'throttled',
    'NewMode' => 'running',
    'reason' => 'just a test'
  );
  return; # leave no value
}

######################################################################
sub test_setup_post()
######################################################################
{
  test_setup_hdr();
  $body = $hdr{__BODY__};
  $user = 'alexander.bartolich@gmx.at';
  $modify_headers = 0;
  return; # leave no value
}

######################################################################
sub test_print_post()
######################################################################
{
  printf "modify_headers=%d\n", $modify_headers;
  test_print_hdr;
}

######################################################################
