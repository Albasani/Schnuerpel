######################################################################
#
# $Id: ScoreReferences.pm 564 2011-08-11 22:02:26Z alba $
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
# Implements interface "on_article"
#
######################################################################

package Schnuerpel::OnArticle::ScoreReferences;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &new
);

use strict;
use Carp qw( confess );
use Date::Parse();
use DBI();

use Schnuerpel::Config qw(
  &DB_DATABASE
  &DB_PASSWD
  &DB_USER
);

######################################################################
# configuration
######################################################################

use constant DEBUG => 1;

use constant SQL_INSERT_POSTING =>
  "INSERT r_filtered_posting(id, date, filter_type, generation)\n" .
  "VALUES(?, ?, ?, ?)\n";
use constant SQL_INSERT_REFERENCE =>
  "INSERT r_filtered_reference(id, reference)\n" .
  "VALUES(?, ?)\n";
use constant SQL_SELECT_TYPE =>
  "SELECT id FROM r_filter_type WHERE name = ?\n";

######################################################################
sub new($$)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  my $generation = shift();
  if (!defined($generation))
    { confess "Missing parameter 'generation'."; }
  $self->{generation} = $generation;

  return $self;
}

######################################################################
sub connect($)
######################################################################
{
  my $self = shift || confess;
  my $msg = 'connect: ';

  unless(defined(DB_DATABASE))
  {
    $msg .= 'Internal error, DB_DATABASE not configured.';
    warn $msg;
    return $msg;
  }

  my $dbc = DBI->connect(
    DB_DATABASE, DB_USER, DB_PASSWD,
    { PrintError => 0, AutoCommit => 1 }
  );
  if (defined( $dbc ))
  {
    $self->{dbc} = $dbc;
    if ($self->{sth_insert_posting} =
      $dbc->prepare( SQL_INSERT_POSTING ))
    {
      if ($self->{sth_insert_reference} =
        $dbc->prepare( SQL_INSERT_REFERENCE ))
      {
        return undef;
      }

      $msg .= 'DBI->prepare (INSERT_POSTING) failed.';
    }
    else { $msg .= 'DBI->prepare (INSERT_REFERENCE) failed.'; }
  }
  else { $msg .= 'DBI->connect failed.' }

  $msg .= "\n" . $DBI::errstr;
  warn $msg;
  return $msg;
}

######################################################################
sub set_type_name($$)
######################################################################
{
  my $self = shift || confess;
  my $name = shift || confess;

  my $dbc = $self->{dbc} || confess;
  my $r_row = $dbc->selectrow_arrayref(SQL_SELECT_TYPE, {}, $name);
  if (!defined( $r_row ))
    { die "Invalid type name $name: $DBI::errstr"; }
  $self->{filter_type} = 0 + $r_row->[0];
}

######################################################################
sub on_article($$;$)
######################################################################
{
  my $self = shift || confess;
  my %param = @_;
  my $article = $param{'article'} || confess;

  my $filter_type = $self->{filter_type};
  confess if (!defined($filter_type));
  my $generation = $self->{generation};
  confess if (!defined($generation));

  my $id = $article->header('Message-ID');
  if (!defined( $id ))
    { warn "No Message-ID"; return; }
  if ($id !~ m/^<([^<>@]+@[^<>@]+)>$/)
    { warn "Invalid Message-ID $id\n"; return; }
  my $core_id = $1;

  my $sth = $self->{sth_insert_posting} || confess;
  $sth->bind_param(1, $core_id) || die "bind_param: $DBI::errstr";
  # $sth->bind_param(2, $core_reference) || die "bind_param: $DBI::errstr";
  $sth->bind_param(3, $filter_type) || die "bind_param: $DBI::errstr";
  $sth->bind_param(4, $generation) || die "bind_param: $DBI::errstr";
  my $rc = $sth->execute() || die "execute: $DBI::errstr";

  # if ($filter_type != 0) 

  $self->insert_references($core_id, $article->header('References'));
}

######################################################################
sub insert_references($$$)
######################################################################
{
  my $self = shift || confess;
  my $core_id = shift || confess;
  my $references = shift;

  return if (!defined($references));
  my $sth = $self->{sth_insert_reference} || confess;

  for my $reference(split(/\s+/, $references))
  {
    if ($reference !~ m/^<([^<>@]+@[^<>@]+)>$/)
    {
      warn "Invalid reference $reference in <$core_id>\n";
      return;
    }
    my $core_reference = $1;
    $sth->bind_param(1, $core_id) || die "bind_param: $DBI::errstr";
    $sth->bind_param(2, $core_reference) || die "bind_param: $DBI::errstr";
    my $rc = $sth->execute() || die "execute: $DBI::errstr";
    # if $rc != 1 the insert failed, probably a duplicate
  }
}

######################################################################
1;
######################################################################
