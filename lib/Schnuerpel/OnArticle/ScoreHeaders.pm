######################################################################
#
# $Id: ScoreHeaders.pm 564 2011-08-11 22:02:26Z alba $
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
# Implements interface "on_article"
#
######################################################################

package Schnuerpel::OnArticle::ScoreHeaders;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use Date::Parse();
use Data::Dumper qw( Dumper );
use News::Article();

use constant DEBUG => 2;
use constant THRESHOLD_FILE => 'headers';
use constant NO_SCORE_FILE => '_+00';

######################################################################
sub new($$)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  $self->{'score_defs'} = shift() || confess "Parameter score_defs missing";

  return $self;
}

######################################################################
sub on_article($@)
######################################################################
{
  my $self = shift || confess;
  my %param = @_;

  my News::Article $article = $param{'article'} || confess;

  my $id = $article->header('Message-ID') ||
    confess 'No "Message-ID" in $article->header';
  return if (exists( $self->{'score'}->{$id} ));

  my $r_headers = $article->rawheaders();
  my $r_score_defs = $self->{'score_defs'} ||
    confess 'No "score_defs" in $self';
  my $time = get_posting_timestamp($article);

  if (DEBUG)
  {
    printf "# OnArticle::score %s time=%d <now=%d #=%d\n",
      $id, $time, $time < time(), $#$r_score_defs;
  }
  
  my $result_score = 0;
  my $result_scoredef = undef;
  my @jury;
  my $score_nr = 0;
  score_def: for my $r(@$r_score_defs)
  {
    confess "Undefined header definition $score_nr" unless(defined($r));
    if (DEBUG > 1)
    {
      printf "# OnArticle::score %s score_nr=%d begin=%d end=%d\n",
        $id, $score_nr, $time < $r->{'begin'}, $time > $r->{'end'};
    }
    $score_nr++;
    if ($time < $r->{'begin'} || $time > $r->{'end'})
    {
      if (DEBUG > 1)
      {
	print "# OnArticle::score Article not in time range.\n";
      }
      next;
    }

    my $pro_pattern = $r->{'pro'} || confess 'No pro pattern';
    my $con_pattern = $r->{'con'} || confess 'No con pattern';

    my $pro_headers = '';
    my $pro_score = 0;
    for my $header(@$r_headers)
    {
      my $pro_item = &$pro_pattern( $header );
      if ($pro_item)
      {
	if ($header =~ m/^([\w-]+:)/) { $pro_headers .= $1; }
	$pro_score += $pro_item;
      }
      if (&$con_pattern( $header ))
      {
	if ($header =~ m/^([\w-]+:)/)
	  { push @jury, sprintf("--- %s %s", $r->{'name'}, $1); }
	next score_def;
      }
    }

    if ($pro_score > 0)
    {
      if ($pro_score >= $r->{'threshold'})
      {
	push @jury, sprintf("+++ %s %s",
  	  $r->{'name'}, $pro_headers);
	my $filename = $r->{'type'} . '/' . THRESHOLD_FILE;
	$self->{'score'}->{$id} = [ $article, \@jury, $filename ];
	return;
      }
      push @jury, sprintf("%3d %s %s",
        $pro_score, $r->{'name'}, $pro_headers);
      if ($pro_score > $result_score)
      {
	$result_score = $pro_score;
	$result_scoredef = $r;
      }
    }
  }

  my $filename = (defined( $result_scoredef ))
  ? sprintf('%s/%s+%02d', $result_scoredef->{'type'},
    $result_scoredef->{'name'}, $result_score)
  : NO_SCORE_FILE;

  $self->{'score'}->{$id} = [ $article, \@jury, $filename ];
}

######################################################################
sub print_score($;$)
######################################################################
{
  my $self = shift || confess;

  my $r_score = $self->{'score'} || return;
  while(my ($id, $r) = each(%$r_score))
  {
    my ( $article, $r_jury, $filename ) = @$r;
    if ($filename =~ m/\+(\d+)$/)
      { printf "# score %3d %s\n", $1, $id; }
    else
      { printf "# score +++ %s\n", $id; }
  }
}

######################################################################
sub open_header_file($)
######################################################################
{
  my $filename = shift;

  my $file;
  if ($filename =~ m#^([^/]+)/#)
  {
    my $type = $1;
    if (! -d $type)
    {
      mkdir($type, 0775) || die "mkdir $type: $!";
    }
    open($file, '>>', $filename) || die "Can't open file $filename: $!";
    printf $file "# type=[%s]\n", $type;
  }
  else
  {
    open($file, '>>', $filename) || die "Can't open file $filename: $!";
  }
  return $file;
}

######################################################################
sub write_header_files($$)
######################################################################
{    
  my $self = shift || confess;
  my $r_tags = shift || confess 'No parameter r_tags';

  my $r_score = $self->{'score'} || return;

  my $base = $r_tags->{'-base'} || confess 'No tag "-base"';

  my $type = $r_tags->{'-type'};
  $type = $base if (!defined( $type ));

  my %file;
  while(my ($id, $r) = each(%$r_score))
  {
    my ( $article, $r_jury, $filename ) = @$r;

    my $file = $file{$filename};
    if (!defined($file))
    {
      $file{$filename} = $file = open_header_file($filename);
      while(my ($key, $value) = each %$r_tags)
      {
	next if (!defined($value));
        $key =~ m/^-*(.*)/;
        printf $file "# %s=[%s]\n", $1, $value;
      }
    }

    for(my $i = 0; $i <= $#$r_jury; $i++)
    {
      printf $file "# jury.%d=[%s]\n", $i, $r_jury->[$i];
    }
    my $r_header = $article->rawheaders();
    print $file join("\n", @$r_header), "\n\n";
  }
}

######################################################################
1;
######################################################################
