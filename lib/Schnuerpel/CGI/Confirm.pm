package Schnuerpel::CGI::Confirm;
use base qw( Schnuerpel::CGI::UserMgr );
@EXPORT_OK = qw( new );

use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

######################################################################
sub new($@)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto;
  my ( %self ) = @_;
  my $self = \%self;

  bless($self, $class);
  Schnuerpel::CGI::UserMgr::init($self);

  $self->get_param('hash', '\W');

  return $self;
}

######################################################################
sub db_select_confirm($)
######################################################################
{
  my $self = shift || die;
  my $hash = shift;

  my $time = $self->db_delete_timeslot('r_confirm');
  my $sql =
    "SELECT language\n" .
    "FROM r_confirm\n" .
    "WHERE confirm_hash = ?\n";

  my $row = $self->db_select_row($sql, [ $self->{hash} ]);
  return undef unless(defined($row));
  return $self->set_lang( $row->[0] );
}

######################################################################
sub main()
######################################################################
{
  my $self = shift;

  if (!defined( $self->db_select_confirm() ))
  {
    $self->print_error('confirm_key');
    return;
  }
}

######################################################################
1;
######################################################################
