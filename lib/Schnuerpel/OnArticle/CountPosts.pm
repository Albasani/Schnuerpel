######################################################################
#
# $Id: CountPosts.pm 635 2011-12-30 18:04:48Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Implements interface "on_article"
#
######################################################################

package Schnuerpel::OnArticle::CountPosts;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use News::Article();
use Schnuerpel::NewsArticle qw( get_posting_timestamp );

use constant CLIENT_FIELDS => [
  'User-Agent', 'X-Newsreader', 'X-Mailer TOP100'
];

######################################################################
sub new($@)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = { @_ };
  bless ($self, $class);

  $self->{'rh_year_month_group_id'} ||= {};
  $self->{'match_group'} ||= '^';

  return $self;
}

######################################################################
sub on_article($@)
######################################################################
{
  my $self = shift || confess;
  my %param = @_;

  my News::Article $article = $param{'article'} || confess 'Undefined $param{"article"}';
  my $group_param = $param{'group'} || confess 'Undefined $param{"group"}';

  my $id = $article->header('Message-ID') ||
    confess 'No "Message-ID" in $article->header';

  my $timestamp = eval { get_posting_timestamp($article); };
  if ($@) { warn $@ . "\nPosting ignored."; return; }

  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst)
    = localtime($timestamp);
  $month++;
  $year += 1900;

  my $match_group = $self->{'match_group'};
  $self->{'rh_id'}->{$id}++;
  for my $group(split(/\s*,+\s*/, $group_param))
  {
    if ($group !~ $match_group) { next; }

    my $r_id = $self->{'rh_year_month_group_id'}->
      {$year}->
	{$month}->
	  {$group}->
	    {$id} ||= {};

    # defined($param{'bytes'}) || confess 'Undefined $param{"bytes"}';
    if ($param{'bytes'}) { $r_id->{'bytes'} = $param{'bytes'}; }

    # $param{'lines'} is the total number of lines in post
    # defined($param{'lines'}) || confess 'Undefined $param{"lines"}';
    # $r_id->{'lines'} = $param{'lines'};
    $r_id->{'lines'} = $article->lines(); # lines in body

    my $ra_fields = CLIENT_FIELDS;
    for my $field(@$ra_fields)
    {
      my $value = $article->header($field);
      if ($value)
      {
	# Cut off at "/":
	#	  40tude_Dialog/2.0.15.1
	#	  ForteAgent/6.00-32.1186  Hamster/2.1.0.11
	#	  Mozilla/5.0 (Windows NT 6.0; WOW64; rv:5.0) Gecko/20110624 Thunderbird/5.0
	#	  XP2 (CrossPoint)/3.31.006-Beta (DOS16/WinXP)
	#	  slrn/pre0.9.9-111 (Linux)
	#	  tin/1.9.6-20100522 ("Lochruan") (UNIX) (Linux/2.6.28.7 (i686))
	#   G2/1.0
	#   MT-NewsWatcher/3.5.2b1 (Intel Mac OS X)
	#   Pan/0.135 (Tomorrow I'll Wake Up and Scald Myself with Tea; GIT 30dc37b master)

	# Cut off at "\s\d":
	#   Microsoft Outlook Express 6.00.2900.3664
	#   Thunderbird 1.5.0.12 (Windows/20070509)

	# Cut off at "\s\(":
	#   Thunderbird (Macintosh; Intel Mac OS X)

	# Note: If both "a" and "b" of "a|b" match then it is undefined
	# whether "a" or "b" is taken. Repeated substitution is necessary
	# to get the shortest client token.

	while($value =~
	  s/ (?:
	       \/ |
	       \s+[\d\(]
	     ).*$
	   //x
	) {}

	$r_id->{'client'} = $value;
	last;
      }
    }

    my $path = $article->header('Path');
    if (defined($path))
    {
      # Cut off special cases:
      #   !newsfe06.iad.POSTED!5e050065!not-for-mail
      #   !feeder.eternal-september.org!.POSTED.184.100.48.123!not-for-mail
      #   !news.dizum.com!sewer-output!mail2news

      $path =~ s/(
	!\.POSTED(?:\.\d+){4}!not-for-mail |
	!sewer-output!mail2news |
	\.POSTED![[:xdigit:]]{8}!not-for-mail
      $)//x;

      # Extraordinary cases:
      #   !newsp.newsguy.com!news6
      #   !news.belnet.be!unknown!not-for-mail
      $path =~ s/(!newsp\.newsguy\.com)!news\d$/$1/;
      $path =~ s/(!news\.belnet\.be)!unknown!not-for-mail$/$1/;

      # Cut off generic trailing elements
      while($path =~ s/(?:!not-for-mail|!\.POSTED)$//)
      {}

      $path =~ s/\.POSTED$//;	# trim news.arcor.de.POSTED
      $path =~ s/^.*!//;		# cut off all but last element

      # Aggregate special names:
      #	l18g2000yql.googlegroups.com
      #	nnrp9-1.free.fr
      #   newsreader03.highway.telekom.at
      $path =~ s/ ^ [\w.-]+ \.
	(
	  free\.fr |
	  googlegroups\.com |
	  highway\.telekom\.at
	) $
      /*.$1/x;

      $r_id->{'path'} = $path;
    }
  }
}

######################################################################
sub get_year_month_group_id($)
######################################################################
{
  my $self = shift || confess;
  return $self->{'rh_year_month_group_id'};
}

######################################################################
1;
######################################################################
