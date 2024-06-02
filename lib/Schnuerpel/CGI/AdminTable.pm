package Schnuerpel::CGI::AdminTable;
use base qw( Schnuerpel::CGI::UserMgr );
@EXPORT_OK = qw( new );
use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

use DBI();
use POSIX();
use Sys::Syslog qw();

use Schnuerpel::CGI::AdminMgr();
use Schnuerpel::CGI::AdminUser();
use Schnuerpel::CGI::TableCtrl();
use Schnuerpel::CGI::UserMgr();

######################################################################
use constant CMD_CANCEL => 0;
use constant CMD_SHOW => 1;
use constant CMD_DELETE => 2;
use constant CMD_CLEAN => 3;
use constant CMD_ADD => 4;
use constant CMD_CHANGE => 5;
use constant CMD_PASSWORD => 6;
use constant CMD_DELETE_CONFIRM => 7;
use constant CMD_MAIL => 8;

######################################################################
# button mode
use constant BM_TABLE => 3;
use constant BM_ROW => 4;
use constant BM_DELETE => 5;

######################################################################
# element 0: list of table columns (SQL)
# element 1: 1 for radio button, undef for check box
# element 2: from/where-clause
# element 3: (BM_TABLE)  list of table buttons
# element 4: (BM_ROW)    list of row buttons
# element 5: (BM_DELETE) list of row buttons in delete mode

my %TABLE_DEF = (
  'r_remote_address' =>
  [
    [
      'session_hash', 'address', 'FROM_UNIXTIME(timeslot) AS time',
      'captcha_hash'
    ],
    0,
    undef,
    [ CMD_CLEAN ],
    [ CMD_DELETE ],
    [ CMD_DELETE_CONFIRM ],
  ],
  'r_confirm' =>
  [
    [
      'confirm_hash', 'address', 'FROM_UNIXTIME(timeslot) AS time',
      'username', 'sex', 'first_name', 'last_name', 'language'
    ],
    0,
    undef,
    [ CMD_CLEAN ],
    [ CMD_DELETE ],
    [ CMD_DELETE_CONFIRM ],
  ],
  'r_user' =>
  [
    [
      'id', '>id', 'username', 'first_name', 'last_name',
      'DATE_FORMAT(FROM_UNIXTIME(last_login), "%Y-%m-%d") AS last'
    ],
    1,
    undef,
    [ CMD_ADD ],
    [ CMD_CHANGE, CMD_PASSWORD, CMD_MAIL ],
    undef
  ],
  'r_admin' =>
  [
    [
      'id', '>id', 'name', 
	'FROM_UNIXTIME(last_login) AS last'
    ],
    1,
    undef,
    undef,
    undef,
    undef
  ],
  'r_user_change' =>
  [
    [
      'B.name', 'B.name AS admin', 'C.username AS user',
      'DATE_FORMAT(FROM_UNIXTIME(time), "%Y-%m-%d %H:%i") AS time'
    ],
    1,
    " A, r_admin B, r_user C" .
    "\nwhere A.admin = B.id" .
    "\nand A.user = C.id",
    undef,
    undef,
    undef
  ],
  'r_feature_setup' =>
  [
    [ 'id', 'type', 'name' ],
    1,
    undef,
    undef,
    undef,
    undef
  ]
);

######################################################################

# index are CMD_xxx
# element 0: 1 if selection is required
# element 1: button mode (one of BM_xxx)
# element 2: name of button
# element 3: function
my @BUTTON_DEF = (
  [ 0, BM_TABLE,  undef ],
  [ 0, BM_TABLE,  undef ],
  [ 1, BM_ROW,    'delete',	\&on_delete ],
  [ 0, BM_TABLE,  'clean',	\&on_clean ],
  [ 0, BM_TABLE,  'add',	\&on_user_button ],
  [ 1, BM_ROW,    'change',	\&on_user_button ],
  [ 1, BM_ROW,    'password',	\&on_user_button ],
  [ 1, BM_DELETE, 'ConfirmDelete', \&on_delete_confirm ],
  [ 1, BM_ROW,    'mail',	\&on_user_button ],
);

# index are CMD_xxx
my %BUTTON_LABEL = (
  'de' => [
    undef,
    'Abbrechen',
    'Löschen',
    'Aufräumen',
    'Hinzufügen',
    'Ändern',
    'Neues Passwort',
    'Löschen Bestätigen',
    'E-Mail'
  ],
  'en' => [
    undef,
    'Cancel',
    'Delete',
    'Clean up',
    'Add',
    'Change',
    'New Password',
    'Confirm Delete',
    'Email'
  ]
);

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

  my $table = $self->get_param('table', '\W', \%TABLE_DEF);
  $table = 'r_user' unless(defined( $table ));
  $self->{table} = $table;

  $self->{tdef} = $TABLE_DEF{$table} || die "Invalid table '$table'";

  $self->{BASE_MENU} = 'internal';
  $self->{hidden_list} = [ 'view', 'lang', 'table' ];
  $self->{error} = [];

  return $self;
}

######################################################################
sub print_header()
######################################################################
{
  my $self = shift || die;
  my $title = shift;

  $self->{title} = $title if (defined($title));

  Schnuerpel::CGI::UserMgr::print_header($self, 1);
  die 'CGI::Vars failed' unless(defined( CGI::Vars() ));
  die 'No "DBC" in $self' unless(exists( $self->{DBC} ));

  # my $url = CGI::url(-relative);
  my $url = $ENV{SCRIPT_NAME};

  $self->{TABLE_HREF} =
    '<p>' .
    join("\n",
      map { "<a href=\"$url?table=$_\">$_</a>" }
      sort keys %TABLE_DEF
    ) .
    '</p>';

  print $self->get_file('admin/table.header.html');

  my $error = $self->{error};
  if (defined($error))
  {
    for my $a(@$error)
    {
      # substitute modifies its argument, so operate on a copy
      #my $b = $a;
      #$b =~ s#\n#<br/>\n#g;
      printf "<pre style=\"color:red\">%s</pre>\n", $a;
    }
  }
}

######################################################################
sub is_cmd_for_table($$)
######################################################################
{
  my $buttons = shift;
  my $button_cmd = shift;

  return 0 unless(defined($buttons));
  for my $cmd(@$buttons)
  {
    return 1 if ($cmd == $button_cmd);
  }
  return 0;
}

######################################################################
sub check_submit()
######################################################################
{
  my $self = shift() || die;

  my $table = $self->{table} || die;
  my @selected = CGI::param($table);
  my $selected = \@selected if ($#selected >= 0);
  my $button_label = $BUTTON_LABEL{ $self->{lang} };

  my $button_cmd = 0;
  for my $button_def(@BUTTON_DEF)
  {
    my $button_name = $button_def->[2];
    if (defined(CGI::param($button_name)))
    {
      my $label = $button_label->[$button_cmd];
      die "Button $button_cmd has no label" unless (defined($label));
      $self->{title} = $table . ' (' . $label . ')';

      $self->{button_name} = $button_name;

      my $needs_selection = $button_def->[0];
      return ( $button_cmd, $selected ) unless($needs_selection);

      my $button_mode = $button_def->[1];
      unless(is_cmd_for_table(
        $TABLE_DEF{$table}->[$button_mode], $button_cmd
      ))
      { die "Invalid command $button_cmd for $table"; }

      return ( $button_cmd, $selected );

      my $error = $self->{error};
      push @$error, "No item selected. ($button_cmd)";
      last;
    }
    $button_cmd++;
  }
  $self->{title} = $table;

  return ( CMD_SHOW, $selected );
}

######################################################################
sub makeButtonRow($$)
######################################################################
{
  my $self = shift() || die;

  # note that "shift || die" strikes on integer value 0
  my $row_button_index = shift;

  my $result = '';

  die unless(exists( $self->{lang} ));
  die unless(exists( $BUTTON_LABEL{ $self->{lang} } ));
  my $button_label = $BUTTON_LABEL{ $self->{lang} };

  my $tdef = $self->{tdef} || die;
  my $row_button = $tdef->[$row_button_index];

  for my $button(@$row_button)
  {
    my $name = $BUTTON_DEF[$button]->[2];
    unless (defined($name))
    {
      die "Undefined button $button ($row_button_index)";
    }

    $result .= CGI::submit(
      -name => $name,
      -value => $button_label->[$button]
    );
  }

  return $result;
}

######################################################################
sub create_TableCtrl($$)
######################################################################
{
  my $self = shift() || die;
  my $filtered = shift;

  my $table = $self->{table} || die;
  my $tdef = $self->{tdef} || die;
  my $r_fields = $tdef->[0] || die;

  my $tc = Schnuerpel::CGI::TableCtrl->new($table, $r_fields, $tdef->[2]);
  return undef unless( $tc->select_rows($self, $filtered) );
  $tc->add_hidden( $self->{hidden_list} );
  return $self->{table_ctrl} = $tc;
}

######################################################################
sub print_table($$$)
######################################################################
{
  my $self = shift() || die;
  my $title = shift;
  my $selected = shift;

  # note that "shift || die" strikes on integer value 0
  my $row_button_index = shift;

#  {
#    my $table = $self->{table} || die;
#    my $hidden_list = $self->{hidden_list};
#    push @$hidden_list, $table;
#
#    # initial value is required by print_hidden()
#    $self->{$table} = defined($selected) ? $selected->[0] : -1;
#  }

  $self->print_header();
  print "<p>", $self->makeButtonRow(3), "</p>\n";
  $self->{table_ctrl}->printTable(
    $self->{tdef}->[1],
    $self->makeButtonRow($row_button_index),
    $selected
  );
}

######################################################################
sub on_view($$)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;
  my $selected = shift;

#  unless(defined(CGI::param('Cancel')))
#  {
#    if ($self->get_user_param())
#    {
#      $self->view_user();
#      return;
#    }
#  }

  return unless( $self->create_TableCtrl(undef) );
  $self->print_table(undef, $selected, 4);
  return $self->print_footer();
}

######################################################################
sub on_delete($$)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;
  my $selected = shift;

  return unless( $self->create_TableCtrl($selected) );
  $self->print_table(undef, $selected, 5);
  return $self->print_footer();
}

######################################################################
sub do_delete($$$)
######################################################################
{
  my $self = shift || die;
  my $table = shift || die;
  my $key_field = shift || die;
  my $items = shift || die;

  my $sql = "DELETE FROM " . $table . "\n";
  TableCtrl::append_sql_where(\$sql, $key_field, $items);
  return $self->db_execute($sql, $items);
}

######################################################################
sub on_delete_confirm($$)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;
  my $selected = shift;

  my $table = $self->{table} || die;
  my $tdef = $TABLE_DEF{ $table } || die;

  $self->do_delete($table, $tdef->[0]->[0], $selected);

  return unless( $self->create_TableCtrl(undef) );
  $self->print_table($table, undef, 4);
  return $self->print_footer();
}

######################################################################
sub on_clean($)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;
  my $selected = shift;

  my $table = $self->{table} || die;

  $self->db_delete_timeslot($table);
  
  return unless( $self->create_TableCtrl(undef) );
  $self->print_table($table, undef, 4);
  return $self->print_footer();
}

######################################################################
sub on_user_button($)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;
  my $selected = shift;

  CGI::param('cmd', $self->{button_name});
  # CGI::param('lang', $self->{lang});
  if (defined($selected))
  {
    CGI::param('userid', $selected->[0]);
  }
  return 'AdminUser';

#  my $c = AdminUser->new();
#  $c->{userid} = $selected->[0];
#  eval { $c->admin(); };
#  $c->done($@);
#  
#  close STDOUT;
#  exit(0);
#
#  my $target =
#    'user.cgi?cmd='. $self->{button_name} .
#    '&lang=' . $self->{lang};
#  if (defined($selected))
#  {
#    $target .= '&userid=' . $selected->[0];
#  }
#
#  my $tc = TableCtrl->new( $self->{table} );
#  $target .= '&' . $tc->add_params_to_url($self);
#  
#  print CGI::redirect($target);
#  close STDOUT;
#  exit(0);
}

######################################################################
sub main()
######################################################################
{
  my $self = shift || die;

  my $admin = Schnuerpel::CGI::AdminMgr->new( $self );
  $admin->setLastLogin(); # modifies $self->{error}
  $self->{admin} = $admin;

  my ( $cmd, $selected ) = $self->check_submit();
  my $func = $BUTTON_DEF[$cmd]->[3];
  $func = \&on_view unless(defined($func));
  return $self->$func($cmd, $selected);
}

######################################################################
1;
######################################################################
