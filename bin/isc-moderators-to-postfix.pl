#!/usr/bin/perl -sw
#
# $Id: isc-moderators-to-postfix.pl 493 2011-04-23 05:31:47Z alba $
#
# Copyright 2010 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
# Input:
# - A file published by ISC that maps moderation email aliases to
#   the actual email addresses of moderators.
# - Optional: A list of valid newsgroups.
#
# Output:
# - A map suitable for Postfix's virtual_alias_maps statement.
# - Otional: A map suitable for Postfix's transport_maps statement.
######################################################################
use strict;
use Carp;
use Data::Dumper;

# Comma-separated list of relay domains
if (!$::domain) { $::domain = 'moderators.isc.org'; }
@::domain = split(/,/, $::domain);

# List of active groups. Only the first white-space separated word is
# used. This works fine with INN's active-file and INN's newsgroups
# file.
if (!$::active) { $::active = '/var/lib/news/active'; }

# This is a switch: 0 means off, 1 is on.
# If the switch is on and $::active is valid then the groups
# matching VERIFYABLE_GROUPS are verified.
if (!$::verify_groups) { $::verify_groups = undef; }

# Name of file to write errors into.
if (!$::error_file) { $::error_file = undef; }

# Name of file to write rejection statements into.
if (!$::recipient_access) { $::recipient_access = undef; }

# Hierarchies administrated through checkgroups
use constant VERIFYABLE_GROUPS => '^' . join('-|^',
  'at',
  'ba',
  'ch',
  'comp',
  'de',
  'dk',
  'es',
  'fido7',
  'fr',
  'gnu',
  'grisbi',
  'hr',
  'humanities',
  'hun',
  'it',
  'misc',
  'news',
  'nl',
  'pl',
  'pt',
  'rec',
  'sci',
  'soc',
  'talk',
  'uk',
  'us',
  'xs4all',
  'z-netz',
) . '-';

# 2011-03-03 scout.wosm.euroscoutinfo.esperanto triggers a spam trap
# 2011-04-21 tnn's news.iij-mc.co.jp does not exist
use constant IGNORE_GROUPS => join('|', '^scout\.', '^tnn\.');

######################################################################
sub print_error(@)
######################################################################
{
  our $print_error_file;

  if (!$print_error_file)
  {
    if (!$::error_file) { print STDERR @_; return; }
    open($print_error_file, '>', $::error_file) ||
      die "Can't open $::error_file for writing.";
  }
  print $print_error_file @_;
}

######################################################################
sub print_recipient_access($@)
######################################################################
{
  my $group = shift || confess;

  our $print_recipient_access_file;

  if (!$print_recipient_access_file)
  {
    if (!$::recipient_access) { return; }
    open($print_recipient_access_file, '>', $::recipient_access) ||
      die "Can't open $::recipient_access for writing.";
  }

  for my $d(@::domain)
  {
    printf $print_recipient_access_file "%s@%s\tREJECT ", $group, $d;
    print $print_recipient_access_file @_, "\n";
  }
}

######################################################################
sub read_active_groups($)
######################################################################
{
  my $filename = shift || die 'No $filename';
  my $file;
  my $result;

  open($file, '<', $filename) || die "Can't open $filename for reading.";
  while(my $line = <$file>)
  {
    if ($line =~ /^(\S*)\s*(.*)/)
    {
      my $key = $1;
      my $value = $2;
      $key =~ s/\./-/g;
      $result->{$key} = $value;
    }
  }

  return $result;
}

######################################################################
sub expect_anywhere($)
######################################################################
{
  my ( $pattern ) = @_;
  while(my $line = <>)
  {
    return $1 if ($line =~ $pattern);
  }
  die "Unexpected end-of-file. Expected this:\n[$pattern]";
  return 0;
}

######################################################################
sub expect_next($)
######################################################################
{
  my ( $pattern ) = @_;
  my $line = <> || die "Unexpected end-of-file. Expected this:\n[$pattern]";
  return $1 if ($line =~ $pattern);
  die "Protocol mismatch. Expected this:\n[$pattern]\nHave this:[$line]";
}

######################################################################
sub process_groups(;$)
######################################################################
{
  my $active_groups = shift;

  while(my $line = <>)
  {
    # 2010-08-02 weird cases:
    # [relcom-astrology::      moderator@astrologer.ru]
    if ($line =~ /^([a-z0-9_+]+(?:-[a-z0-9_+]+)*):+\t+(.*)/)
    {
      my $group = $1;
      my $addr = $2;

      if ($addr eq '/dev/null' ||
          $addr eq 'mod-bounce.not-exist@isc.org' ||
	  $addr =~ m/^mod-bounce\.[^@]*\@isc\.org/
      )
      {
	print_recipient_access($group, "ISC says " . $addr);
	next;
      }

      for my $d(@::domain)
      {
	if ($addr eq ($group . '@' . $d))
	{
	  print_recipient_access($group, "Recursive alias " . $addr);
	  next;
        }
      }

      # 2010-08-02 weird cases:
      # [comp-lang-perl-announce:       clpa*@stonehenge.com
      # [comp-std-c++:  std-c++@netlab.cs.rpi.edu
      unless($addr =~ /([\w*+-]+)@([\w*+-]+)/)
      {
        print_error "Invalid email address:\n[$line]\n";
	next;
      }

      if ($active_groups &&
          $group =~ &VERIFYABLE_GROUPS() &&
	  !exists($active_groups->{$group})
      ){
        print_error "$group not in group list ($addr)\n";
	next;
      }

      if ($group =~ &IGNORE_GROUPS()) { next; }

      for my $d(@::domain)
      {
        printf "%s@%s\t%s\n", $group, $d, $addr;
      }
    }
    elsif ($line =~ /^#/)
    {
      return 1;
    }
    else
    {
      die "Protocol mismatch. Expected group line. Have this:\n[$line]";
    }
  }
}

######################################################################
# MAIN
######################################################################

my $active_group_list = ($::verify_groups && $::active)
? read_active_groups($::active)
: undef;

expect_anywhere
  '^#  Beginning of list of aliases for posting to moderated groups.';
my $date = expect_next
  '^#  Last update mailed by moderators-request@isc\.org at ([\w\d: ]+)';
expect_next
  '^#';
my $timestamp = expect_next
  '^moderators--timestamp:\s+mod-bounce.(\d+)@isc\.org';

printf "# date      %s\n", $date;
printf "# timestamp %d\n", $timestamp;

process_groups($active_group_list);
