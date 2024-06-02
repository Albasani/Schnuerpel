######################################################################
#
# $Id: ShellVars.pm 628 2011-10-31 08:45:20Z alba $
#
# Copyright 2007-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::ShellVars;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  get_cleanfeed_version
  get_group_status
  $INN_HOME
  load_cleanfeed
  load_innshellvars
  read_active
  read_newsgroups
);
use strict;

# note that %config is set up by cleanfeed

our $INN_HOME;		# value of $HOME set by innshellvars.pl
our $loaded_cleanfeed;	# boolean
our $rh_active;		# contents of active file

######################################################################
sub load_innshellvars()
######################################################################
{
  # innshellvars modifies $ENV{'HOME'}, so save it
  my $original_home = $ENV{HOME};

  for my $file(
    '/usr/lib/news/innshellvars.pl',
    '/usr/lib/news/lib/innshellvars.pl'
  )
  {
    next unless(-f $file);
    # printf "innshellvars.pl=%s\n", $file;
    require $file;
    last;
  }

  unless(defined($inn::perl_filter_innd))
  {
    die "Can't find innshellvars.pl";
  }

  $INN_HOME = $ENV{HOME};
  $ENV{HOME} = $original_home;
}

######################################################################
sub load_cleanfeed()
######################################################################
{
  return 1 if ($loaded_cleanfeed);
  load_innshellvars() if (!defined($inn::perl_filter_innd));

  for my $suffix(
    '/cleanfeed/cleanfeed.local',
    '/cleanfeed/cleanfeed'
  )
  {
    my $file = $inn::pathfilter . $suffix;
    if ( -f $file )
    {
      require $file;
      $loaded_cleanfeed = 1;
      return 1;
    }
  }

  return undef;
  
  # require $inn::pathfilter . '/cleanfeed/cleanfeed.local';
  # local_config();	# call function defined in cleanfeed.local
  # get_config();	# call function defined in file 'cleanfeed'
}

######################################################################
sub get_cleanfeed_version()
######################################################################
{
  return undef if (!load_cleanfeed());

  #
  # First try the interface defined by Steve Crook
  #
  my $version = eval
  {
    no strict;
    get_config();	# call function defined in file 'cleanfeed'
    return ($version && $version_date)
    ? sprintf("%d (%s)", $version, $version_date)
    : undef;
  };
  if ($version) { return $version; }

  #
  # Fall back to the release notes of Marco d'Itri
  #
  my $name = $inn::pathfilter . '/cleanfeed/CHANGES';
  if ( -f $name )
  {
    my $file;
    open($file, '<', $name) || die "Can't open $name: $!";
    while(my $line = <$file>)
    {
      return $1 if ($line =~ m/^== released (\S+)/);
    }
  }

  #
  # No version found.
  #
  return undef;
}

######################################################################
sub read_active(;$)
######################################################################
{
  my $force_reload = shift;

  if ($rh_active && !$force_reload) { return $rh_active; }
  $rh_active = undef;
  if (!defined($inn::active)) { load_innshellvars(); }

  my $file;
  open($file, '<', $inn::active) || die "Can't open $inn::active: $!";
  while(my $line = <$file>)
  {
    chomp($line);
    if ($line =~ m#^\s*(\S+)\s*(.*)?$#)
    {
      my $group = $1;
      my $rest = $2;
      if ($rest)
      {
	my @a = split(/\s+/, $rest);
	$rh_active->{$group} = \@a;
      }
      else
      {
	$rh_active->{$group} = undef;
      }
    }
  }

  return $rh_active;
}

######################################################################
sub get_group_status($)
######################################################################
{
  my $newsgroups = shift;

  my $rh_active = read_active();
  if ($rh_active && $newsgroups)
  {
    for my $group(split(/\s*,\s*/, $newsgroups))
    {
      my $ra_active = $rh_active->{$group};
      if (defined($ra_active))
      {
	my $status = $ra_active->[2];
	if (defined($status))
	{
	  if ($status ne 'y') { return $status; }
        }
      }
    }
  }
  return '';
}

######################################################################
sub read_newsgroups($)
######################################################################
{
  my $r_hash = shift || die;

  load_innshellvars() if (!defined($inn::newsgroups));
  my $file;
  unless(open($file, '<', $inn::newsgroups))
  {
    die "Can't open $inn::newsgroups: $!";
  }
  while(my $line = <$file>)
  {
    $line =~ s/\s+$//;
    unless($line =~ m/^(\S+)\s*(.*)$/)
    {
      printf STDERR "WARNING: Invalid line %d in %s:\n%s\n",
        $., $inn::newsgroups, $line;
      next;
    }
    $r_hash->{$1} = $2;
  }
}

######################################################################
1;
######################################################################
