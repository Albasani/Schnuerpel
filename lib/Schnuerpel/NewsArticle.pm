######################################################################
#
# $Id: NewsArticle.pm 609 2011-08-28 00:08:59Z alba $
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
# Parse and manipulate a few special headers of Usenet posts. This 
# module works with instances of News::Article. See HashArticle.pm
# for similar code that works with the hash of headers provided by
# INN to perl hooks (filter_innd.pl and filter_nnrpd.pl).
#
######################################################################

package Schnuerpel::NewsArticle;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  get_posting_timestamp
);

use strict;
use Carp qw( confess );
use News::Article();

###########################################################################
sub get_posting_timestamp($)
###########################################################################
{
  my News::Article $article = shift || confess;

  my @error_msg;
  my @fields = ( 'NNTP-Posting-Date', 'Injection-Date', 'Date' );
  for my $field(@fields)
  {
    my $timestr = $article->header($field);
    if ($timestr)
    {
      # See <4E0C6972.123C.0030.1@boku.ac.at> for a date field that
      # includes the references header after a line feed.
      $timestr =~ s/^([^\r\n]+).*/$1/;

      my $t = Date::Parse::str2time($timestr);
      if (defined($t)) { return $t; }
      push @error_msg,
	sprintf("Can't parse time string (%s): %s", $field, $timestr);
    }
  }

  if ($#error_msg < 0)
  {
    push @error_msg,
      sprintf("None of %s defined.", join(', ', @fields));
  }
  my $msgid = $article->header('Message-ID');
  if ($msgid) { push @error_msg, 'In message ' . $msgid; }
  die join("\n", @error_msg);
}

######################################################################
1;
######################################################################
