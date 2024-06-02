#!/usr/bin/perl -w
#
# $Id: TestFilter.pm 509 2011-07-20 13:55:30Z alba $
#
# Copyright 2007-2009 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::TestFilter;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  test_script
);
use strict;

# use Carp qw( confess );
use Schnuerpel::INN::ShellVars();

######################################################################
sub test_script($$)
######################################################################
{
  my $file_name = shift || die;
  my $r_func_list = shift || die;

  printf "\n*** %s ***\n", $file_name;
  unless(-f $file_name)
  {
    die "File $file_name does not exist.";
  }
  require $file_name;

  for my $r(@$r_func_list)
  {
    my $func_name = $r->[0];
    next unless(exists( &$func_name ));

    printf "\n=== Calling %s ===\n", $func_name;
    my $func = \&{ $func_name };
    my $func_setup = $r->[1];
    my @rc = &$func( &$func_setup() );

    my $i = 0;
    for my $rc(@rc)
    {
      if (defined($rc))
      {
	printf "%2d: ref=%s length=%d string=%s\n",
	  $i, ref($rc), length($rc), $rc;
      }
      else
      {
	printf "%2d: undef\n", $i;
      }
    }

    printf "\n=== Calling %s (print) ===\n", $func_name;
    my $func_print = $r->[2];
    if (defined($func_print)) { &$func_print(); }
  }
}

######################################################################
# fake INN functions
######################################################################
package INN;

sub addhist($;$$$$)
{
  printf "INN::addhist(%s)\n", join(', ', @_);
  return 1;
}

sub article($)
{
  printf "INN::article(%s)\n", join(', ', @_);
  return undef;
}

sub cancel($)
{
  printf "INN::cancel(%s)\n", join(', ', @_);
  return 1;
}

sub filesfor($)
{
  printf "INN::filesfor(%s)\n", join(', ', @_);
  return 0;
}

sub head($)
{
  printf "INN::head(%s)\n", join(', ', @_);
  return undef;
}

sub newsgroup($)
{
  printf "INN::newsgroup(%s)\n", join(', ', @_);
  return undef;
}

sub syslog($;$)
{
  printf "INN::syslog(%s)\n", join(', ', @_);
}

######################################################################
1;
######################################################################
