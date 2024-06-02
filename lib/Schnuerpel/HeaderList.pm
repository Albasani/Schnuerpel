######################################################################
#
# $Id: HeaderList.pm 637 2011-12-30 21:56:30Z alba $
#
# Copyright 2008-2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# The file format handled by this module:
# - Plain text
# - Only the headers of articles are stored, not the body
# - Articles are separated by a single empty line
# - Lines matching the pattern
#     ^\s*#\s*(\w+)=\[(.*)\]$
#   define pragma settings, e.g.
#     # type=[spam]
#
######################################################################
package Schnuerpel::HeaderList;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &enum_headers_file
);

use strict;
use Carp qw( confess );
use News::Article();

use constant MAXHEADS => 16*1024;

######################################################################
sub finish_article($$$)
######################################################################
{
  my $rh_pragma = shift;
  my $ra_header = shift;
  my $delegate = shift;
  
  if ($#$ra_header >= 0)
  {
    my $article = News::Article->new($ra_header, 0, MAXHEADS);
    if (!$article)
    {
      my $header_string = join("\n", @$ra_header);
      warn sprintf("News::Article->new failed\nlength(\$header_string)=%d\n%s",
	length($header_string),
	$header_string
      );
      return 0;
    }
    my $group = $article->header('Newsgroups');
    if (!$group)
    {
      my $header_string = join("\n", @$ra_header);
      warn sprintf("Undefined header 'Newsgroups'\nlength(\$header_string)=%d\n%s",
	length($header_string),
	$header_string
      );
      return 0;
    }
    $delegate->on_article(
      'article' => $article,
      'rh_pragma' => $rh_pragma,
      'group' => $group
    );
  }
  return 1;
}

######################################################################
sub enum_headers_file(@)
######################################################################
# Named parameters:
# - delegate ... must support interface "on_article"
# - filename ... name of file to read (optional)
#   If filename is not specified then STDIN is read instead.
######################################################################
{
  my %param = @_;
  my $delegate = $param{'delegate'} || confess 'Missing argument "delegate"';
  my $filename = $param{'filename'};

  my $file = \*STDIN;
  if (defined($filename))
  {
    open($file, '<', $filename) ||
      confess "Error: $!\nCan't open file $filename";
  }

  my %pragma;
  my @header;
  while(my $line = <$file>)
  {
    $line =~ s/[\r\n]+$//;

    if ($line =~ m/^\s*$/)
    {
      finish_article(\%pragma, \@header, $delegate);
      undef @header;
    }
    elsif ($line =~ m/^\s*#\s*(\w+)=\[(.*)\]$/)
    {
      $pragma{$1} = $2;
    }
    elsif ($line =~ m/^\s+/)
    {
      if ($#header >= 0) { $header[ $#header ] .= "\n" . $line; }
    }
    else
    {
      push @header, $line;
    }
  }

  if ($#header >= 0)
  {
    finish_article(\%pragma, \@header, $delegate);
  }
}

######################################################################
1;
######################################################################
