######################################################################
#
# $Id: ReplacementFile.pm 133 2008-08-18 20:39:54Z alba $
#
# Copyright 2008 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::ReplacementFile;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw( new );
use strict;

use File::Temp();

######################################################################
sub new($@)
######################################################################
{ 
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my ( %self ) = @_;
  my $self = \%self;

  bless($self, $class);
  return $self;
}

######################################################################
sub open($$)
######################################################################
{ 
  my $self = shift || die;
  my $filename = shift || die "No filename given.";

  $self->{filename} = $filename;
  if (-f $filename)
  {
    my $dir = '';
    my $name = $filename;
    if ($filename =~ m#^(.*/)([^/]+)$#)
    {
      $dir = $1;
      $name = $2;
    }

    my ( $file, $tmp_filename ) = File::Temp::tempfile(
      $name . '.XXXXXX', DIR => $dir, UNLINK => 0
    );
    $self->{tmp_filename} = $tmp_filename;

    if (exists( $self->{chmod} ))
    {
      # printf STDERR "chmod %o %s\n", $self->{chmod}, $self->{filename};
      chmod($self->{chmod}, $tmp_filename)
      || die "Can't chmod $tmp_filename\n$!";
    }
    return $self->{file} = $file;
  }

  my $file;
  open($file, '>', $filename)
  || die "Can't open file $filename\n$!";

  return $self->{file} = $file;

}

######################################################################
sub DESTROY($)
######################################################################
{ 
  my $self = shift || die;

  my $file = $self->{file};
  $file->close();
  undef $self->{file};

  return unless(exists( $self->{tmp_filename} ));

  my $msg = '';
  unless(unlink( $self->{filename} ))
  {
    $msg = sprintf(
      "Can't unlink %s\nError: %s.", $self->{tmp_filename}, $!
    );
  }

  return if (rename($self->{tmp_filename}, $self->{filename}));
  die sprintf(
    "Can't rename %s to %s\nError: %s.\n%s",
    $self->{tmp_filename}, $self->{filename}, $!, $msg
  );
}

######################################################################
1;
######################################################################
