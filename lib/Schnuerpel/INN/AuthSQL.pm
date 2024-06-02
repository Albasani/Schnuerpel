#
# $Id: AuthSQL.pm 543 2011-07-31 20:37:44Z alba $
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
# See etc/auth for usage and configuration.
#
######################################################################

package Schnuerpel::INN::AuthSQL;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &sql_access
  &sql_auth
  &sql_disconnect
  &sql_get_features
  &sql_get_user
  &sql_get_user_id
  &sql_init
  &sql_newsgroup_access
  &sql_log_post
);
use strict;

use Carp qw( confess );
use DBI();
# use DBI qw(:sql_types);

use Schnuerpel::Config qw(
  &DB_DATABASE
  &DB_USER
  &DB_PASSWD
  &LOCAL_PATH_ID
);

use Schnuerpel::HashArticle qw(
  get_pruned_path
  get_posting_timestamp
);

######################################################################
# configuration
######################################################################

use constant DEBUG => 1;

use constant MAX_USER_ID => 2**31;

use constant DEFAULT_NEWSGROUPS => '*,!junk';

use constant SQL_USE_PASSWD_NONE =>
  "UPDATE r_user\n" .
  "SET last_login = UNIX_TIMESTAMP(), last_host = ?\n" .
  "WHERE username = ?\n" .
  "AND status = 1\n";

use constant SQL_USE_PASSWD_PLAIN =>
  SQL_USE_PASSWD_NONE .
  "AND passwd_plain = ?\n";

use constant SQL_USE_PASSWD_HT =>
  SQL_USE_PASSWD_NONE .
  "AND encrypt(?, left(passwd_ht, 2)) = passwd_ht\n";

use constant SQL_GET_USER =>
  "SELECT id, created, last_login, last_host, status\n" .
  "FROM r_user\n" .
  "WHERE username = ?\n";

use constant SQL_GET_FEATURES =>
  "SELECT A.type, A.name, B.value\n" .
  "FROM r_feature_setup A, r_feature B\n" .
  "WHERE B.feature = A.id\n" .
  "AND B.user = ?\n" .
  "AND B.value > 1\n";

use constant SQL_RECORD_POST =>
  "INSERT INTO r_local_post\n" .
  "(%s)\n" .
  "VALUES(%s)\n";

use constant SQL_GET_CONTROL_SETUP =>
  "SELECT id, name\n".
  "FROM r_control_setup\n" .
  "WHERE name <> ''\n";

use constant SQL_LOG_NEWSGROUPS =>
  "INSERT INTO r_local_post_group\n" .
  "(id, group_nr, group_name)\n" .
  "VALUES( LAST_INSERT_ID(), ? , ? )";

######################################################################
sub sql_init()
######################################################################
{
  if (defined($::dbc)) { return undef; }

  my $msg = 'sql_init: ';

  unless(defined(DB_DATABASE))
  {
    $msg .= 'Internal error, DB_DATABASE not configured.';
    return $msg;
  }

  $::dbc = DBI->connect(DB_DATABASE, DB_USER, DB_PASSWD,
    { PrintError => 0, AutoCommit => 1 });
  return undef if (defined( $::dbc ));

  $msg .= "DBI->connect failed.\n" . $DBI::errstr;
  return $msg;
}

######################################################################
sub sql_execute($;$)
######################################################################
# Return value is ( $rows_affected, $error_text )
######################################################################
{  
  my $query = shift || confess;
  my $r_values = shift;

  {
    my $msg = sql_init();
    if ($msg) { return ( 0, $msg ); }
  }

  my $sth = $::dbc->prepare($query);
  if (!defined( $sth ))
  {
    my $msg = 'database error, prepare failed.';
    if ($::dbc->err)
      { $msg .= ' ' . $::dbc->err; }
    if ($::dbc->errstr)
      { $msg .= ' ' . $::dbc->errstr; }
    return ( 0, $msg );
  }

  if (DEBUG > 2)
  {
    if (defined($r_values))
    {
      INN::syslog('N', "query=$query; values=" . join(',', @$r_values));
    }
    else
    {
      INN::syslog('N', "query=$query; no values");
    }
  }

  # man DBI
  # An "undef" is returned if an error occurs. A successful "execute"
  # always returns true regardless of the number of rows affected,
  # even if it's zero. [...] For a non-"SELECT" statement, "execute"
  # returns the number of rows affected, if known. If no rows were
  # affected, then "execute" returns "0E0", which Perl will treat as
  # 0 but will regard as true. Note that it is not an error for no
  # rows to be affected by a statement. If the number of rows affected
  # is not known, then "execute" returns -1.

  my $rc = defined($r_values)
  ? $sth->execute(@$r_values)
  : $sth->execute();
  if (!defined($rc))
  {
    my $msg = 'database error, execute failed.';
    if ($::dbc->err)
      { $msg .= ' ' . $::dbc->err; }
    if ($::dbc->errstr)
      { $msg .= ' ' . $::dbc->errstr; }
    return ( 0, $msg );
  }

  return ( $rc, undef );
}

######################################################################
# Return value is ( $confidence, $nntp_code, $error_text )
# $confidence == +1 ... successful authentication
# $confidence ==  0 ... authentication failed, try next module
# $confidence == -1 ... authentication failed, abort
######################################################################
sub sql_auth($;$$)
######################################################################
{
  my $username = shift || die 'No username';
  my $password = shift;
  my $hostname = shift;

  # Response code 403
  # Generic response
  # Meaning: internal fault or problem preventing action being taken.

  if (!$username) { return ( 0, 403, 'SQL authenticate: No username' ); }

  my $msg = sql_init();
  return ( 0, 403, $msg ) if (defined($msg));

  $msg = 'SQL authenticate ' . $username . ': ';
  if (DEBUG > 2 && defined($password))
    { INN::syslog('N', "sql_auth trying $username $password"); }
  elsif (DEBUG > 1)
    { INN::syslog('N', "sql_auth trying $username"); }

  my $sql = SQL_USE_PASSWD_NONE;
  my @values = ( $hostname, $username );
  if (defined($password))
  {
    $sql = SQL_USE_PASSWD_PLAIN;
    push @values, $password;
  }

  my ( $rows_affected, $execute_msg ) = sql_execute($sql, \@values);
  if (defined($execute_msg)) { return ( 0, 403, $msg . $execute_msg ); }

  if ($rows_affected == 1)
  {
    # this message is searched by onno-send-login.awk
    my $msg = 'SQL authenticated ' . $username;
    if ($hostname) { $msg .= ' ' . $hostname; }
    INN::syslog('N', $msg);

    # According to RFC 4643 response code 281 means
    # "Authentication accepted".

    $::authenticated{module} = 'SQL';
    return ( +1, 281, undef );
  }

  $msg .= "login failed, rc=$rows_affected";

  #
  # Warning: sql_get_user may recursively call sql_init if $::dbc
  # is not defined.
  #
  sql_get_user($username, 0);
  my $status = $::authenticated{status};
  if (!defined($status))
    { $msg .= ', unknown user'; }
  elsif ($status != 1)
    { $msg .= ', invalid status ' . $status; }

  my $detail = $msg;
  if (DEBUG && defined($password))
    { $detail .= ', password=' . $password; }
  INN::syslog('W', $detail);

  # According to RFC 4643 response code 481 means
  # "Authentication failed/rejected".
  return ( 0, 481, $msg );
}

######################################################################
sub sql_get_user($;$)
######################################################################
{
  my $username = shift || die 'No username';
  my $die_on_error = shift;

  $::authenticated{'username'} = $username;

  if (!defined($::dbc))
  { #
    # sql_init was not called yet. Perhaps readers.conf does
    # authentication by IP address only, without password.
    # Call sql_auth to update login timestamp.
    #
    # Warning: sql_auth may recursively call sql_get_user if user
    # does not exist.
    #
    my ( $confidence, $rc, $msg ) = sql_auth($username, undef);
    if (defined($msg))
    {
      die $msg if ($die_on_error);
      $::authenticated{id} = MAX_USER_ID;
      return [ MAX_USER_ID ];
    }
    defined($::dbc) || confess "No database connection";
  }

  my $row = $::dbc->selectrow_arrayref(SQL_GET_USER,
    undef, $username);
  if (defined($row))
  {
    $::authenticated{id} = $row->[0];
    $::authenticated{created} = $row->[1];
    $::authenticated{last_login} = $row->[2];
    $::authenticated{last_host} = $row->[3];
    $::authenticated{status} = $row->[4];
    return $row;
  }
  if (!$die_on_error)
  {
    $::authenticated{id} = MAX_USER_ID;
    return [ MAX_USER_ID ];
  }

  my $msg = 'access/get_user ' . $username . ': database error';
  if ($::dbc->err) { $msg .= ' ' . $::dbc->err; }
  if ($::dbc->errstr) { $msg .= ' ' . $::dbc->errstr; }
  die $msg;
}

######################################################################
sub sql_get_user_id()
######################################################################
{
  my $user_id = $::authenticated{id};
  if (!defined($user_id))
  {
    my $username = $::attributes{username} || die 'No username';
    sql_get_user($username, 0);
    $user_id = $::authenticated{id} || die 'No user ID';
  }
  return $user_id;
}

######################################################################
sub sql_get_features(;$)
######################################################################
{
  my $userid = $_[0];
  if (!defined($userid)) { $userid = sql_get_user_id(); }
  if (!defined($::dbc)) { die 'No $dbc'; }

  my $rows = $::dbc->selectall_arrayref(SQL_GET_FEATURES,
    undef, $userid);
  return $rows if (defined($rows));

  my $msg .= 'access/get_features ' . $userid . ': database error';
  if ($::dbc->err) { $msg .= ' ' . $::dbc->err; }
  if ($::dbc->errstr) { $msg .= ' ' . $::dbc->errstr; }
  die $msg;
}

######################################################################
sub sql_disconnect()
######################################################################
{
  if (defined($::dbc))
  {
    $::dbc->disconnect();
    undef $::dbc;
  }
}

######################################################################
sub sql_newsgroup_access(;$$)
######################################################################
{
  my ( $uid_perms, $newsgroups ) = @_;

  if (!$newsgroups) { $newsgroups = DEFAULT_NEWSGROUPS; }
  if (!defined($uid_perms)) { return $newsgroups; }

  #
  # Default values based on user id or creation date.
  #

  my $user_id = sql_get_user_id();
  for my $p(@$uid_perms)
  {
    $newsgroups .= $p->[ $user_id > $p->[0] ? 2 : 1 ];
  }
  return $newsgroups;
}

######################################################################
sub sql_access(;$$)
######################################################################
{
  my ( $newsgroups, $access_mode ) = @_;

  if (!$newsgroups) { $newsgroups = DEFAULT_NEWSGROUPS; }
  if (!$access_mode) { $access_mode = 'RPNA'; }

  my $username = $::attributes{username};

  #
  # Override with explicit features
  #
  my $rows = sql_get_features();
  for my $row(@$rows)
  {
    my ( $type, $name, $value ) = @$row;
    if (DEBUG)
    {
      INN::syslog('N', "username=$username type=$type feature=[$name] value=$value");
    }
    if ($type == 1)
    {
      my $letter = substr($name, 0, 1);
      $access_mode =~ s/$letter//gx;
      $access_mode .= $letter if ($value == 2);
    }
    elsif ($type == 2)
    {
      my $pattern = "\Q$name\E";
      $newsgroups =~ s/^ !? $pattern (,|$)//x;
      $newsgroups =~ s/, !? $pattern (,|$)/$1/x;
      $newsgroups .= ',' if (length($newsgroups) > 0);
      $newsgroups .= '!' if ($value != 2);
      $newsgroups .= $name;
    }
  }

  #
  # Return result hash
  #
  my %result = (
    'access' => $access_mode,
    'read' => $newsgroups,
    'users' => $username
  );
  $result{'post'} = $newsgroups if ($access_mode =~ /P/);

  return %result;
}

######################################################################
sub sql_get_control_setup()
######################################################################
{
  if ($::authenticated{'control_setup'})
    { return $::authenticated{'control_setup'}; }

  my $msg = sql_init();
  if ($msg)
  {
    INN::syslog('E', 'sql_get_control_setup: ' . $msg);
    return undef;
  }

  my $r = $::dbc->selectcol_arrayref(
    SQL_GET_CONTROL_SETUP,
    { Columns => [2, 1] }
  );
  if (!$r)
  {
    INN::syslog('E', 'sql_get_control_setup: selectcol_arrayref failed.');
    return undef;
  }

  my %hash = @$r; # build hash from key-value pairs so $hash{$name} => id
  return $::authenticated{'control_setup'} = \%hash;
}

######################################################################
sub sql_log_post_groups($)
######################################################################
{
  my $r_hdr = shift || confess;
  my $msg = 'sql_log_post_groups: DB error, ';

  my $sth = $::dbc->prepare(SQL_LOG_NEWSGROUPS);
  if (!defined( $sth ))
  {
    $msg .= 'prepare failed.';
    if ($::dbc->err)
      { $msg .= ' ' . $::dbc->err; }
    if ($::dbc->errstr)
      { $msg .= ' ' . $::dbc->errstr; }
    INN::syslog('E', $msg);
    return $msg;
  }

  my @group_nr;
  my @group_name;

  my $groups = $r_hdr->{'Newsgroups'};
  if ($groups)
  {
    my $group_nr = 0;
    for my $group_name( split(/\s*,\s*/, $groups) )
    {
      push @group_nr, ++$group_nr;
      push @group_name, $group_name;
    }
  }

  $groups = $r_hdr->{'Followup-To'};
  if ($groups)
  {
    my $group_nr = 0;
    for my $group_name( split(/\s*,\s*/, $groups) )
    {
      push @group_nr, --$group_nr;
      push @group_name, $group_name;
    }
  }

  my $nr_tuples = $sth->execute_array({}, \@group_nr, \@group_name);
  if (!defined( $nr_tuples ))
  {
    $msg .= 'execute_array failed.';
    if ($::dbc->err)
      { $msg .= ' ' . $::dbc->err; }
    if ($::dbc->errstr)
      { $msg .= ' ' . $::dbc->errstr; }
  }
  elsif ($nr_tuples != $#group_nr + 1)
  {
    $msg .= 'execute_array returned ' . $nr_tuples .
      ', expected ' . ($#group_nr + 1);
  }
  else { return undef; }

  INN::syslog('E', $msg);
  return $msg;
}

######################################################################
sub sql_log_post($;$)
######################################################################
{
  my $r_hdr = shift || confess;
  my $cancel_key = shift;

  my $message_id = $r_hdr->{'Message-ID'};
  if (!$message_id) { return 'sql_log_post: No Message-ID in $r_hdr'; }
  my $msg = 'sql_log_post ' . $message_id . ': ';

  # Message-ID is stored without angle brackets
  $message_id =~ s/^<([^>]+)>$/$1/;

  my $timestamp = eval { get_posting_timestamp($r_hdr); };
  if ($@) { $timestamp = time(); }

  my @values = ( $message_id, $timestamp );
  my @columns = ( 'h_message_id', 'timestamp' );

  if ($::authenticated{'id'})
  {
    push @values, $::authenticated{'id'};
    push @columns, 'userid';
  }
  if ($::authenticated{'username'})
  {
    push @values, $::authenticated{'username'};
    push @columns, 'username';
  }
  if ($cancel_key)
  {
    push @values, $cancel_key;
    push @columns, 'h_cancel_key';
  }

  my $from = $r_hdr->{'From'};
  if ($from) { push @values, $from; push @columns, 'h_from'; }
  
  my $path = get_pruned_path( $r_hdr->{'Path'}, LOCAL_PATH_ID );
  if ($path) { push @values, $path; push @columns, 'h_path'; }

  my $control = $r_hdr->{'Control'};
  if ($control)
  {
    # A typical value for $control looks like this:
    # cancel <i6l7jt$mkh$1@four.albasani.net>
    $control =~ s/\s.*$//; # we only need the first word

    my $r_setup = sql_get_control_setup();
    # sql_get_control_setup reports errors via syslog
    if ($r_setup)
    {
      my $control_id = $r_setup->{$control};
      if ($control_id)
      {
	push @values, $control_id;
	push @columns, 'h_control';
      }
      else
      {
        INN::syslog('W', $msg . 'undefined control ' . $control);
      }
    }
  }

  # rt, LAST_INSERT_ID() and mysql_insert_id()

  my $query = sprintf(SQL_RECORD_POST,
    join(', ', @columns),
    join(', ', map { '?' } @columns)
  );

  my ( $rows_affected, $execute_msg ) = sql_execute($query, \@values);
  if (defined($execute_msg)) { $msg .= $execute_msg; }
  elsif ($rows_affected != 1) { $msg .= "rc=$rows_affected"; }
  else { return sql_log_post_groups($r_hdr); }
  INN::syslog('E', $msg);
  return $msg;
}

######################################################################
1;
######################################################################
