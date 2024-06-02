######################################################################
#
# $Id: ScoreXPAT.pm 563 2011-08-11 19:12:31Z alba $
#
# Copyright 2008-2009 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::ScoreXPAT;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw( scoreXPAT );

use strict;
use Carp qw( confess );
# use Net::NNTP();
# use News::Newsrc();

use Schnuerpel::NNTP();
use Schnuerpel::NewsrcNNTP qw(
  enum_newsrc_range
  get_newsrc
);
use Schnuerpel::OnArticle::ScoreHeaders qw();
use Schnuerpel::OnMsgSpec::LoadArticle qw();
use Schnuerpel::OnMsgSpec::xpat qw();

######################################################################
sub scoreXPAT(@)
######################################################################
{
  my %args = @_;

  my $newsrc_file = $args{-newsrc} ||
    confess "Missing argument '-newsrc'";
  my $scoredef = $args{-scoredef} ||
    confess "Missing argument '-scoredef'";
  my $xpatdef = $args{-xpatdef} ||
    confess "Missing argument '-xpatdef'";

  my $r_nntp = Schnuerpel::NNTP::connect();
  unless(defined($r_nntp))
    { die 'Can\'t connect to NNTP server'; }
  my Net::NNTP $nntp = $r_nntp->{'nntp'} || confess;

  my $oa_score = Schnuerpel::OnArticle::ScoreHeaders->new($scoredef);
  my $head = Schnuerpel::OnMsgSpec::LoadArticle->new(
    'nntp' => $nntp,
    'delegate' => $oa_score
  );
  my $xpat = Schnuerpel::OnMsgSpec::xpat->new($nntp, $xpatdef, $head);

  my $groups = $args{-groups};
  my News::Newsrc $newsrc = get_newsrc($nntp, $newsrc_file, $groups);
  unless(defined($newsrc))
    { die 'Can\'t load file ' . $newsrc_file; }

  eval { enum_newsrc_range($nntp, $xpat, $newsrc); };
  if ($@) { warn $@; }
  $newsrc->save();

  my $r_tags = $args{-tags};
  $r_tags = {} if (!defined($r_tags));

  if (!defined( $r_tags->{-base} ))
  {
    $newsrc_file =~ m#([^/]+)(?:\.[^/]*)*$#;
    $r_tags->{-base} = $1;
  }

  if (!defined( $r_tags->{-tlh} ) && defined($groups))
  {
    $groups =~ m#^([^,.*]+)#;
    $r_tags->{-tlh} = $1;
  }

  $oa_score->print_score();
  $oa_score->write_header_files($r_tags);
}

######################################################################
1;
######################################################################
