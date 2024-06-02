#!/usr/bin/perl -ws
#
# $Id: get-retention.pl 654 2012-06-30 21:57:31Z root $
#
# Copyright 2011-2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

use strict;
# use Carp qw( confess );
# use Data::Dumper;
use Net::NNTP();
use Date::Parse();

use constant DEFAULT_GROUPS =>
  'comp.*,humanities.*,misc.*,news.*,rec.*,sci.*,soc.*,talk';

use constant USAGE =>
  "USAGE:\n" .
  "  get-retention.pl { OPTION }\n" .
  "\n" .
  "OPTIONS:\n" .
  "  -help\n" .
  "    Write this text and exit.\n" .
  "\n" .
  "  -server=host\n" .
  "  -server=host:port\n" .
  "    If this option is not given then environment variable NNTPSERVER\n" .
  "    is used instead.\n" .
  "    The port number defaults to 119.\n" .
  "    Examples:\n" .
  "      -server=nntp.aioe.org\n" .
  "      -server=reader.albasani.net\n" .
  "      -server=reader.albasani.net:119\n" .
  "\n" .
  "  -groups=pattern\n" .
  "  -groups=pattern,pattern\n" .
  "     This option defaults to all groups of the BIG8, i.e.\n" .
  "     -groups=" . DEFAULT_GROUPS . "\n" .
  "\n" .
  "AUTHENTICATION\n" .
  "  Username and password are read from the file \$HOME/.slrnrc\n".
  "  If this file does not exist or does not contain suitable entries then\n" .
  "  no authentication is used.\n" .
  "  Get-retention.pl understands only a tiny subset of the slrnrc file format,\n" .
  "  namely the nnrpaccess statement. All other lines are ignored.\n" .
  "  The second word of this statement must exactly match the server parameter.\n" .
  "  Second and third word specify username and password.\n" .
  "  Example:\n" .
  "    nnrpaccess reader.albasani.net    \"readonly\" \"readonly\"\n" .
  "    nnrpaccess reader.albasani.net:80 \"readonly\" \"readonly\"\n" .
  "\n";

use constant SECONDS_PER_DAY => 60 * 60 * 24;

######################################################################
sub read_slrnrc(;$)
######################################################################
{
  my $server_unquoted = shift || die;
  my $server_quoted = '"' . $server_unquoted . '"';

  my $name = $ENV{'HOME'} . '/.slrnrc';
  open(my $file, '<', $name) || die "Can't open file $name: $!";
  while(my $line = <$file>)
  {
    my @a = split /\s+/, $line;
    if ($#a <= 1 || $a[0] ne 'nnrpaccess') { next; }
    if ($a[1] ne $server_quoted && $a[1] ne $server_unquoted) { next; }
    
    my $user = $a[2];
    if ($user) { $user =~ s/^"(.*)"$/$1/; }
    my $password = $a[3];
    if ($password) { $password =~ s/^"(.*)"$/$1/; }
    printf "Found username %s for %s\n", $user, $server_unquoted;
    return ( $user, $password );
  }
  return undef;
}

######################################################################
sub connect_nntp($$$)
######################################################################
{
  my $server = shift || die 'No $server';
  my $user = shift;
  my $password = shift;

  my $nntp = Net::NNTP->new(
    Host => $server,
    Debug => 0,
    Reader => 1
  );
  if (!$nntp) { die "Can't connect to " . $server; }

  # first message after connect is server signature
  my $server_sig = $nntp->message();
  print $server_sig;

  if ($user && $password)
  {
    if (!$nntp->authinfo($user, $password))
    {
      die sprintf(
	"Error: Authentication failed for host=%s\nuser=%s pass=%s",
	$server, $user, $password
      );
    }
  }

  $nntp->date();
  my $msg = $nntp->message();
  # cut off the trailing '\n' returned by Net::NNTP::message
  $msg =~ s/\s+$//;
  printf "Server date: %s\n", $msg;

  return $nntp;
}

######################################################################
sub get_overview_indexes($$)
######################################################################
{
  my Net::NNTP $nntp = shift || die;
  my $ra_required = shift || die;

  my $ra_fmt = $nntp->overview_fmt();
  if (!$ra_fmt)
  {
    die sprintf("overview_fmt failed: %s\n", $nntp->message());
  }

  my $index = 0;
  my $rh_field_to_index;
  for my $field(@$ra_fmt)
  {
    $rh_field_to_index->{ $field } = $index;
    ++$index;
  }

  for my $field(@$ra_required)
  {
    if (!exists($rh_field_to_index->{ $field })) 
    {
      die "Field $field not found in overview. overview_fmt="
	. join(', ', @$ra_fmt);
    }
  }

  printf "Overview fields: %s\n", join(', ', @$ra_fmt);
  return $rh_field_to_index;
}

######################################################################
sub get_overview_fields($$$)
######################################################################
{
  my Net::NNTP $nntp = shift || die;
  my $article_id = shift;
  my $expected_max_index = shift || die;

  die unless(defined($article_id));
  die unless($article_id >= 0);

  my $rh_article_to_overview = $nntp->xover($article_id);
  if (!$rh_article_to_overview)
  {
    die sprintf(
      "xover(%d) returned undef: %s",
      $article_id, $nntp->message()
    );
  }

  my $ra_fields = $rh_article_to_overview->{ $article_id };
  if (!defined($ra_fields))
  {
    die sprintf("xover(%d) failed: %s", $article_id, $nntp->message());
  }

  if ($#$ra_fields != $expected_max_index)
  {
    die sprintf(
      "xover(%d) returned broken result (%s): %s",
      $article_id,
      join(", ", @$ra_fields),
      $nntp->message()
    );
  }

  return $ra_fields;
}

######################################################################
sub get_article_age($$$)
######################################################################
{
  my $rh_get = shift || die;
  my $ra_article_id = shift || die;
  my $group_name = shift || die;

  my $nntp = $rh_get->{'nntp'} || die;
  my $debug = $rh_get->{'debug'};
  my $now = $rh_get->{'now'} || time();
  my $date_index = $rh_get->{'date_index'};
  my $msgid_index = $rh_get->{'msgid_index'};
  my $max_overview_index = $rh_get->{'max_overview_index'};
  my @ra_fields;

  for my $article_id( @$ra_article_id )
  {
    eval
    {
      my $ra_fields = get_overview_fields(
	$nntp, $article_id, $max_overview_index
      );
      my $date_str = $ra_fields->[ $date_index ];
      my $time = Date::Parse::str2time($date_str);
      if (!defined($time))
      {
	die sprintf("str2time(\"%s\") failed.", $date_str);
      }

      my $age_in_days = int(($now - $time) / SECONDS_PER_DAY);
      push @ra_fields, [
	$age_in_days,
	$date_str,
	$ra_fields->[ $msgid_index ]
      ];
    };
    if ($@ && $debug)
    {
      # cut off the trailing '\n' returned by Net::NNTP::message
      $@ =~ s/\s+$//;
      printf "Error with group %s, article %d: %s\n",
	$group_name, $article_id, $@;
    }
  }

  my @result = sort { $a->[0] <=> $b->[0] } @ra_fields;
  return \@result;
}

######################################################################
sub get_retention($$$)
######################################################################
{
  my $rh_get = shift || die;
  my $ra_group_pattern = shift || die;
  my $rh_empty_groups = shift || die;

  my $nntp = $rh_get->{'nntp'} || die;
  my $now = $rh_get->{'now'} || time();
  my $debug = $rh_get->{'debug'};

  my %result;
  for my $pattern(@$ra_group_pattern)
  {
    if ($debug)
    {
      printf "# Searching group pattern %s\n", $pattern;
    }
    my $rh_active = $nntp->active($pattern);
    while(my ($group_name, $ra_active) = each %$rh_active)
    {
      my ( $nr_articles, $last_article, $first_article, $group_name_2 ) =
	$nntp->group( $group_name );
      if (!defined($nr_articles))
      {
	printf "ERROR: Can't change into group %s: %s\n",
	  $group_name, $nntp->message();
	next;
      }

      my $flags = $ra_active->[2];
      if ($nr_articles == 0)
      {
	$rh_empty_groups->{$group_name} = $flags;
	next;
      }

      # The results of 'active' and 'group' sometimes differ. Try both numbers.
      my @article_id = ( int($last_article) );
      for my $article_id($ra_active->[0], $first_article, $ra_active->[1])
      {
	if ($article_id != $article_id[ $#article_id ])
	  { push @article_id, int($article_id); }
      }

      my $ra_ra_fields = get_article_age($rh_get, \@article_id, $group_name);
      if ($#$ra_ra_fields < 0)
      {
	$rh_empty_groups->{$group_name} = $flags;
	next;
      }

      $result{$group_name}->{'flags'} = $flags;
      $result{$group_name}->{'nr_articles'} = $nr_articles;
      $result{$group_name}->{'min_age'} = $ra_ra_fields->[0];
      $result{$group_name}->{'max_age'} = $ra_ra_fields->[ $#$ra_ra_fields ];
    }
  }

  return \%result;
}

######################################################################
sub print_empty($)
######################################################################
{
  my $rh_empty_groups = shift || die;

  my $name = 'empty.txt';
  open(my $file, '>', $name) || die "Can't open file $name: $!";

  print $file
    "# Column f: y=posting allowed, m=moderated\n" .
    "# f name\n";
  for my $group( sort(keys(%$rh_empty_groups)) )
  {
    printf $file "%3s %s\n", $rh_empty_groups->{$group}, $group;
  }
}

######################################################################
sub print_verbose($$$)
######################################################################
{
  my $file = shift || die;
  my $ra_group_name = shift || die;
  my $rh_group_to_rh_ra_fields = shift || die;

  for my $group_name(@$ra_group_name)
  {
    my $rh_ra_fields = $rh_group_to_rh_ra_fields->{ $group_name };
    my $ra_min = $rh_ra_fields->{'min_age'};
    my $ra_max = $rh_ra_fields->{'max_age'};
    printf $file "%s\n  %5d articles, %s\n  %s\n  %s\n",
      $group_name,
      $rh_ra_fields->{'nr_articles'},
      $rh_ra_fields->{'flags'},
      join(", ", @$ra_min),
      join(", ", @$ra_max);
  }
}

######################################################################
sub print_brief($$$)
######################################################################
{
  my $file = shift || die;
  my $ra_group_name = shift || die;
  my $rh_group_to_rh_ra_fields = shift || die;

  print $file
    "# Columns min, max give article age in days.\n" .
    "# Column nr is the number of articles.\n" .
    "# Column flg: y=posting allowed, m=moderated\n" .
    "#  min    max     nr flg name\n";
  for my $group_name(@$ra_group_name)
  {
    my $rh_ra_fields = $rh_group_to_rh_ra_fields->{ $group_name };
    printf $file "%6d %6d %6d %3s %s\n",
      $rh_ra_fields->{'min_age'}->[0],
      $rh_ra_fields->{'max_age'}->[0],
      $rh_ra_fields->{'nr_articles'},
      $rh_ra_fields->{'flags'},
      $group_name;
  }
}

######################################################################
sub read_data($$$)
######################################################################
{
  my $server = shift || die;
  my $group_list = shift || die;
  my $rh_empty_groups = shift || die;

  my ( $user, $password ) = read_slrnrc($server);
  my $nntp = connect_nntp($server, $user, $password);
  my $rh_field_to_index = get_overview_indexes($nntp,
    [ 'Date:', 'Message-ID:' ]
  );

  my $rh_get = {
    'nntp' => $nntp,
    'debug' => $::debug,
    'now' => time(),
    'rh_field_to_index' => $rh_field_to_index,
    'date_index' => $rh_field_to_index->{ 'Date:' },
    'msgid_index' => $rh_field_to_index->{ 'Message-ID:' }
  };
  {
    my @fields = keys(%$rh_field_to_index);
    $rh_get->{'max_overview_index'} = $#fields;
  }

  my @group_list = split /,/, $group_list;
  my $rh_group_to_rh_ra_fields =
    get_retention($rh_get, \@group_list, $rh_empty_groups);
  # print Dumper($rh_group_to_rh_ra_fields), "\n";
}

######################################################################
sub print_data($)
######################################################################
{
  my $rh_group_to_rh_ra_fields = shift || die;

  my @group = sort {
    $rh_group_to_rh_ra_fields->{$a}->{'min_age'}->[0] <=>
    $rh_group_to_rh_ra_fields->{$b}->{'min_age'}->[0] 
  } keys(%$rh_group_to_rh_ra_fields);

  {
    my $name = 'brief.txt';
    open(my $file, '>', $name) || die "Can't open file $name: $!";
    print_brief($file, \@group, $rh_group_to_rh_ra_fields);
  }
  {
    my $name = 'verbose.txt';
    open(my $file, '>', $name) || die "Can't open file $name: $!";
    print_verbose($file, \@group, $rh_group_to_rh_ra_fields);
  }
}

######################################################################
# MAIN
######################################################################

if (!$::help) { $::help = undef; }
if (!$::debug) { $::debug = undef; }
if (!$::server) { $::server = $ENV{'NNTPSERVER'}; }
if (!$::groups) { $::groups = DEFAULT_GROUPS; }

if ($::help || !$::server || !$::groups) { print USAGE; exit; }

my %empty_groups;
my $rh_group_to_rh_ra_fields = read_data($::server, $::groups,
  \%empty_groups);
print_empty(\%empty_groups);
print_data($rh_group_to_rh_ra_fields);

######################################################################
