package Schnuerpel::CGI::AdminMgr;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw( new );

use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

use DBI();
use Sys::Syslog qw();
use Schnuerpel::CGI::UserMgr qw(
  &DEBUG_SQL
  &MYSQL_ON_DUPLICATE
);

######################################################################
sub new($$)
######################################################################
{
  my $proto = shift || die;
  my $usermgr = shift || die;

  my $class = ref($proto) || $proto;
  my %self = (
    'usermgr' => $usermgr,
    'user' => $ENV{'REMOTE_USER'}
  );
  my $self = \%self;

  bless($self, $class);

  return $self;
}

######################################################################
sub selectAdminID($)
######################################################################
{
  my $self = shift() || die;
  my $usermgr = $self->{usermgr} || die;
  my $user = $self->{user} || die;

  my $dbc = $usermgr->{DBC};

  my $sql =
    "SELECT id\n" .
    "FROM r_admin\n" .
    "WHERE name = ?\n";
  my $row = $usermgr->db_select_row($sql, [ $user ]);
  return 0 unless(defined($row));
  $self->{adminid} = $row->[0];
  return 1;
}

######################################################################
sub setLastLogin($)
######################################################################
{
  my $self = shift() || die;
  my $usermgr = $self->{usermgr} || die "No usermgr (internal error)";
  my $user = $self->{user} || die "No username (is web server configured for authentication?)";

  if (MYSQL_ON_DUPLICATE)
  {
    my $sql =
      "INSERT INTO r_admin\n" .
      "(name, last_login)\n" .
      "VALUES (?, UNIX_TIMESTAMP())\n" .
      "ON DUPLICATE KEY UPDATE\n" .
      "last_login = UNIX_TIMESTAMP()\n";
    my $rc = $usermgr->db_execute($sql, [ $user ]);
    return defined($rc) && $self->selectAdminID();
  }
  else
  {
    my $sql =
      "UPDATE r_admin\n" .
      "SET last_login = UNIX_TIMESTAMP()\n" .
      "WHERE name = ?\n";
    my $rc = $usermgr->db_execute($sql, [ $user ]);
    return 0 unless(defined($rc));

    if ($rc != 1)
    {
      my $sql =
	"INSERT INTO r_admin\n" .
	"(name, last_login)\n" .
	"VALUES (?, UNIX_TIMESTAMP())\n";
      my $rc = $usermgr->db_execute($sql, [ $user ], 1);
      return 0 unless(defined($rc));
    }
    return $self->selectAdminID();
  }
}

######################################################################
1;
