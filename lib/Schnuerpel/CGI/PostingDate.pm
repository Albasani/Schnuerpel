#!/usr/bin/perl -w

package Schnuerpel::CGI::PostingDate;

use strict;
use encoding 'utf8';

my @ISA = qw(Exporter);
my @EXPORT = qw( new );

use constant WEEKDAY => {
  'Sun' => 0, 'Mon' => 1, 'Tue' => 2, 'Wed' => 3,
  'Thu' => 4, 'Fri' => 5, 'Sat' => 6
};
use constant MONTH => {
  'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4,
  'May' => 5, 'Jun' => 6, 'Jul' => 7, 'Aug' => 8,
  'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12
};

use constant FORMAT => '%04d-%02d-%02d ';

# --------------------------------------------------------------------------
sub parse($;$)
# --------------------------------------------------------------------------
{
  my $date = shift;
  my $r_timezone = shift;

  if (defined($r_timezone) && $date =~ m#([A-Z]{3}|\+\d{4})#)
    { $$r_timezone = $1; }

  return ($1, $2, $3)
  if ($date =~ m#([0-9]{4})/([0-9]{2})/([0-9]{2})\s*#);

  # 434@sdcrdcf.UUCP features
  # Date: Mon, 8-Aug-83 21:33:55 EDT
  # so split on dash as well
  my @word = split /[\s,-]+/, $date;

  # cut off weekday, if present, case insensitive:
  # Message-ID: <dtOMcmVb1BSzV6Munospam@invalid>
  # Date: tue, 2 jan 2007 22:41:00 +0100
  shift(@word) if (defined( WEEKDAY->{ ucfirst($word[0]) } ));

  my ( $monthday, $month, $year );
  if ($word[0] =~ m/^\d+$/)
  {
    $monthday = int($word[0]);
    $month = ucfirst( MONTH->{$word[1]} );
    $year = $word[2];
  }
  else
  {
    # <anews.Aunc.850> features
    # Date: Thu May 28 21:40:54 1981
    $monthday = int($word[1]);
    $month = MONTH->{$word[0]};
    $year = $word[3];
  }
  return undef if (!defined($month));
  return ($year, $month, $monthday);
}

# --------------------------------------------------------------------------
1;
