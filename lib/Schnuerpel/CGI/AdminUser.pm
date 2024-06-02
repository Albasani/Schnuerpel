package Schnuerpel::CGI::AdminUser;
use base qw( Schnuerpel::CGI::UserMgr );
@EXPORT_OK = qw( new init );
use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

use Schnuerpel::CGI::AdminMgr();
use DBI();
use Sys::Syslog();

use Schnuerpel::CGI::Globals qw(
  @LANG
  %LANG
);
use Schnuerpel::CGI::UserMgr qw(
  &GET_PARAM_DATE
  &GET_PARAM_EMAIL
  &GET_PARAM_INT
  &GET_PARAM_LANG
  &GET_PARAM_PASSWORD
  &LANG_DEFAULT
);
use Schnuerpel::RandPasswd();

######################################################################
use constant CMD_CANCEL           => 0;
use constant CMD_ADD              => 1;
use constant CMD_CHANGE           => 2;
use constant CMD_PASSWORD         => 3;
use constant CMD_CONFIRM_ADD      => 4;
use constant CMD_CONFIRM_CHANGE   => 5;
use constant CMD_CONFIRM_PASSWORD => 6;
use constant CMD_MAIL             => 7;

######################################################################
# index are CMD_xxx

my %TITLE = (
  'de' => [
    undef,
    'Benutzer hinzufügen',
    'Benutzer ändern',
    'Neues Passwort',
    'Neuer Benutzer',
    'Benutzer geändert',
    'Passwort geändert',
    'E-mail schicken',
  ],
  'en' => [
    undef,
    'Add user',
    'Change user',
    'New password',
    'New user',
    'Changed user',
    'Changed password',
    'Send email',
  ]
);

######################################################################
# index are CMD_xxx

my @BUTTON_DEF = (
  undef,
  \&on_add,
  \&on_change,
  \&on_password,
  \&on_confirm_add,
  \&on_confirm_change,
  \&on_confirm_password,
  \&on_email,
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
  $self->init();
  return $self;
}

######################################################################
sub init($)
######################################################################
{
  my $self = shift || die;

  Schnuerpel::CGI::UserMgr::init($self);
  $self->{BASE_MENU} = 'internal';
  $self->{hidden_list} = [ 'view', 'lang', 'cmd', 'table',

    # these params are used by TableCtrl.pm
    # exact name depends on value of table
    # hardcoding them here is ugly
    'start_r_user', 'sort_r_user'
  ];

  $self->{error} = [];
  # $self->{language} = UserMgr::LANG_DEFAULT;
}

######################################################################
sub get_command($$)
######################################################################
{
  my $self = shift || die;
  my $userid = shift;

  return CMD_CANCEL if (defined(CGI::param('Cancel')));
  return CMD_CONFIRM_ADD if (defined(CGI::param('ConfirmAdd')));
  return CMD_CONFIRM_CHANGE if (defined(CGI::param('ConfirmChange')));
  return CMD_CONFIRM_PASSWORD if (defined(CGI::param('ConfirmPassword')));
  return CMD_CHANGE if (defined(CGI::param('change')));
  if (defined($userid))
  {
    my $cmd = CGI::param('cmd');
    if ($cmd + 0 != 0)
    {
      return $cmd;
    }
    if (defined($cmd))
    {
      return CMD_CHANGE if ($cmd eq 'change');
      return CMD_ADD if ($cmd eq 'add');
      return CMD_PASSWORD if ($cmd eq 'password');
      return CMD_MAIL if ($cmd eq 'mail');
    }
  }
  return CMD_ADD;
}

######################################################################
sub print_header()
######################################################################
{
  my $self = shift || die;
  my $title = shift;

  $self->{title} = $title if (defined($title));

  Schnuerpel::CGI::UserMgr::print_header($self, 1);
  die unless(defined( CGI::Vars() ));
  die unless(exists( $self->{DBC} ));

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
sub get_user_param()
######################################################################
{
  my $self = shift || die;

  &Schnuerpel::CGI::UserMgr::get_user_param($self);

  $self->get_param('created', GET_PARAM_DATE);
  $self->get_param('last_login', GET_PARAM_DATE);
  $self->get_param('passwd_plain', GET_PARAM_PASSWORD);
  $self->get_param('email', GET_PARAM_EMAIL);
  $self->get_param(
    'language', GET_PARAM_LANG, \%LANG
  );
  $self->get_param('status', GET_PARAM_INT);
  $self->get_param('send_email', GET_PARAM_INT);
}

######################################################################
sub set_user_form()
######################################################################
{
  my $self = shift || die;

  Schnuerpel::CGI::UserMgr::set_user_form($self);

  $self->{INPUT_EMAIL} = CGI::textfield(
    -id => 'input_email',
    -name => 'email',
    -size => 64,
    -value => $self->{email}
  );

  my $language = exists( $self->{language} )
  ? $self->{language} 
  : LANG_DEFAULT;
  $self->{INPUT_LANGUAGE} = CGI::popup_menu(
    -id => 'input_language',
    -name => 'language',
    -values => \@LANG,
    -default => $language
  );

  $self->{INPUT_PASSWORD} = CGI::textfield(
    -id => 'input_password',
    -name => 'passwd_plain',
    -size => 64,
    -value => $self->{passwd_plain}
  );

  my $status = exists( $self->{status} ) 
  ? $self->{status}
  : '1';
  $self->{INPUT_STATUS_ACTIVE} = $self->radio_button('status', '1');
  $self->{INPUT_STATUS_SIGNED_OFF} = $self->radio_button('status', '2');
  $self->{INPUT_STATUS_CLOSED} = $self->radio_button('status', '3');
}

######################################################################
sub select_user_features()
######################################################################
{
  my $self = shift || die;

  my @bind;
  my $sql = '';
  if (exists($self->{userid}))
  {
    $sql .=
      "SELECT A.id, A.name, B.value\n" .
      "FROM r_feature_setup A\n" .
      "LEFT JOIN r_feature B\n" .
      "ON (B.feature = A.id AND B.user = ?)\n" .
      "ORDER BY A.id\n";
    push @bind, $self->{userid};
  }
  else
  {
    $sql .=
      "SELECT A.id, A.name, 1\n" .
      "FROM r_feature_setup A\n";
  }
  my $rows = $self->db_select_all($sql, \@bind);
  unless(defined($rows) && $#$rows >= 0)
  {
    delete $self->{user_features};
    return undef;
  }
  return $self->{user_features} = $rows;
}

######################################################################
sub get_user_feature_data()
######################################################################
{
  my $self = shift || die;
  my $rows = $self->select_user_features();
  return undef unless(defined($rows));

  for my $row(@$rows)
  {
    $self->{feature_label} = $row->[1];
    my $name = 'feature_' . $row->[1];
    my $value = $self->get_param($name, GET_PARAM_INT);
    if (defined($value))
      { $row->[2] = $value + 0; }
  }

  return $rows;
}

######################################################################
sub set_user_features()
######################################################################
{
  my $self = shift || die;

  my $rows = $self->select_user_features();
  my $fields = '';
  for my $row(@$rows)
  {
    $self->{feature_label} = $row->[1];
    my $name = 'feature_' . $row->[1];
    my $value = $self->get_param($name, GET_PARAM_INT);
    unless(defined($value))
    {
      $value = $row->[2] + 0;
    }
    for my $i(1, 2, 3)
    {
      my $input = "<input type=\"radio\" name=\"$name\" value=\"$i\"";
      if ($i eq $value)
	{ $input .= ' checked="checked"'; }
      $self->{'INPUT_FEATURE_' . $i} = $input . "/>\n";
    }
    $self->{'INPUT_SEND_MAIL'} = sprintf(
      '<input type="checkbox" name="send_email" value="1"%s/>',
      $self->{'send_email'} ? ' checked="checked"' : ''
    );
    $fields .= $self->get_file('admin/user/feature_row.html');
  }
  $self->{INPUT_FEATURE_FIELDS} = $fields;
}

######################################################################
sub do_select_by_username($)
######################################################################
{
  my $self = shift() || die;
  my $ok = 0;

  eval
  {
    my $username = $self->{username} || die;
    my $sql =
      "SELECT\n" .
      "  id,\n" .
      "  FROM_UNIXTIME(created, '%Y-%m-%d %h:%i'),\n" .
      "  FROM_UNIXTIME(last_login, '%Y-%m-%d %h:%i'),\n" .
      "  status\n" .
      "FROM r_user\n" .
      "WHERE username = ?\n";
    my $row = $self->db_select_row($sql, [ $username ]);
    unless(defined($row))
    {
      die "username=$username\n$sql\n" . $self->{DBC}->errstr();
    }

    $self->{userid} = $row->[0] if defined($row->[0]);
    $self->{created} = $row->[1] if defined($row->[1]);
    $self->{last_login} = $row->[2] if defined($row->[2]);
    $self->{status} = $row->[3] if defined($row->[3]);
    $ok = 1;
  };
  if ($@)
  {
    my $r = $self->{error};
    push @$r, $@;
  }
  return $ok;
}

######################################################################
sub do_select_by_userid($)
######################################################################
{
  my $self = shift() || die;

  my $userid = $self->{userid} || die "No userid";

  my $sql =
    "SELECT\n" .
    "  FROM_UNIXTIME(created, '%Y-%m-%d %h:%i'),\n" .
    "  FROM_UNIXTIME(last_login, '%Y-%m-%d %h:%i'),\n" .
    "  username, first_name, last_name, email, sex,\n" .
    "  language, passwd_plain, status\n" .
    "FROM r_user\n" .
    "WHERE id = ?\n";
  my $row = $self->db_select_row($sql, [ $userid ]);
  unless(defined($row))
  {
    die "userid=$userid\n$sql\n" . $self->{DBC}->errstr();
  }

  $self->{created} = $row->[0] if defined($row->[0]);
  $self->{last_login} = $row->[1] if defined($row->[1]);
  $self->{username} = $row->[2] if defined($row->[2]);
  $self->{first_name} = $row->[3] if defined($row->[3]);
  $self->{last_name} = $row->[4] if defined($row->[4]);
  $self->{email} = $row->[5] if defined($row->[5]);
  $self->{sex} = $row->[6] if defined($row->[6]);
  $self->{language} = $row->[7] if defined($row->[7]);
  $self->{passwd_plain} = $row->[8] if defined($row->[8]);
  $self->{status} = $row->[9] if defined($row->[9]);
}

######################################################################
sub get_user_data($$)
######################################################################
{
  my $self = shift() || die;
  my $r_add_hidden = shift() || die;

  $self->do_select_by_userid() unless(exists( $self->{created} ));
  my $hidden_list = $self->{hidden_list};
  push @$hidden_list, @$r_add_hidden;
}

######################################################################
sub view_user($$;$)
######################################################################
{
  my $self = shift() || die;
  my $template = shift() || die;
  my $r_add_hidden = shift;

  $self->get_user_data($r_add_hidden) if (defined($r_add_hidden));
  $self->print_header();
  $self->set_user_form();
  print $self->get_file($template);
}

######################################################################
sub generate_password()
######################################################################
{
  my $self = shift() || die;

  #
  # Warning: Produced characters must not match GET_PARAM_PASSWORD
  #
  # my $passwd = Crypt::RandPasswd::random_chars_in_range( 24, 24, '0', 'z');

  my $passwd = Schnuerpel::RandPasswd::random_chars_in_range(
    24, 24, '0', 'z'
  );

  # remove characters that are hard to type or read
  $passwd =~ s#[<>\[\]\\^`_?0O1lI5Sqg:;]+#-#g;

  # trim adjacent non-word characters
  $passwd =~ s#(\W)\W+#$1#g;

  # remove non-word characters at the beginning 
  $passwd =~ s#^\W+##;

  # remove non-word characters starting at the 8th character
  $passwd =~ s#^(.{7})\W+(.*)$#$1$2#;

  $passwd = substr($passwd, 0, 8);
  CGI::param( 'passwd_plain', $self->{passwd_plain} = $passwd );
}

######################################################################
sub on_add($)
######################################################################
{
  my $self = shift() || die;

  $self->{cmd} = CMD_ADD;
  unless(exists( $self->{passwd_plain} ))
  {
    $self->generate_password();
    $self->{send_email} = 1;
  }

  $self->set_user_features(1);
  $self->view_user('admin/user/add.html');
  return $self->print_footer();
}

######################################################################
sub on_change($)
######################################################################
{
  my $self = shift() || die;

  $self->set_user_features(0);
  $self->view_user(
    'admin/user/change.html',
    [ 'userid', 'created', 'last_login' ]
  );
  return $self->print_footer();
}

######################################################################
sub on_password($)
######################################################################
{
  my $self = shift() || die;

  $self->get_user_data(
    [ 'username', 'first_name', 'last_name', 'email',
    'language', 'userid', 'created', 'last_login' ]
  );
  if (defined(CGI::param('GeneratePassword')))
    { $self->generate_password(); }
  $self->view_user('admin/user/password.html');
  return $self->print_footer();
}

######################################################################
sub seedchar()
######################################################################
{
  return ('a'..'z','A'..'Z','0'..'9','.','/')[rand(64)];
}

######################################################################
sub crypt_password()
######################################################################
{
  my $self = shift || die;

  my $plain = $self->{passwd_plain};
  if (defined($plain) && length($plain) > 0)
  {
    $self->{passwd_ht} = crypt($plain, seedchar() . seedchar());
    return 1;
  }
  else
  {
    undef( $self->{passwd_ht} );
    return 0;
  }
}

######################################################################
sub do_add($)
######################################################################
{
  my $self = shift || die;
  my $rc;

  eval
  {
    $self->crypt_password();
    my @field_name = (
      'username', 'first_name', 'last_name', 'email', 'sex',
      'language', 'passwd_plain', 'passwd_ht'
    );

    my $first =
      "INSERT INTO r_user(\n" .
      "  created";
    my $second =
      "\n" .
      ") VALUES(UNIX_TIMESTAMP()";
    my @bind;

    for my $field(@field_name)
    {
      $first .= ', ' . $field;

      my $value = $self->{$field};
      $value =~ s#\s*$##;
      if (defined($value) && length($value) > 0)
      {
	push @bind, $value;
	$second .= ', ?';
      }
      else
      {
	$second .= ', null';
      }
    }
    $rc = $self->db_execute($first . $second . ")\n", \@bind, 1);
  };
  if ($@)
  {
    my $r = $self->{error};
    push @$r, $@;
    return 0;
  }
  return defined($rc);
}

######################################################################
sub do_add_features($)
######################################################################
{
  my $self = shift || die;

  my $rc;
  eval
  {
    my $userid = $self->{userid} || die;
    my $rows = $self->get_user_feature_data();
    if (defined($rows))
    {
      my $sql =
	"INSERT INTO r_feature(user, feature, value)\n" .
	"VALUES ";
      my $separator = '';
      my @bind;
      for my $row(@$rows)
      {
        my $value = $row->[2];
	# ignore the default value, 1
        if (defined($value) && $value != 1)
	{
	  $sql .= $separator;
	  $sql .= '(?, ?, ?)';
	  $separator = ",\n";
	  push @bind, $userid, $row->[0], $value;
        }
      }
      if ($#bind >= 0)
      {
	$rc = $self->db_execute($sql, \@bind, ($#bind + 1) / 3);
      }
    }
  };
  if ($@)
  {
    my $r = $self->{error};
    push @$r, $@;
    return 0;
  }
  return defined($rc);
}

######################################################################
sub compare_field($$$)
######################################################################
{
  my $self = shift || die;
  my $orig = shift || die;
  my $field = shift || die;

  my $new_value = $self->{$field};
  my $orig_value = $orig->{$field};

  if (!defined($orig_value) || length($orig_value) == 0)
  {
    return (defined($new_value) && length($new_value) > 0) ? 1 : 0;
  }
  if (!defined($new_value) || length($new_value) == 0)
  {
    return 2;
  }
  return $orig->{$field} eq $self->{$field} ? 0 : 1;
}

######################################################################
sub get_orig_user($)
######################################################################
{
  my $self = shift || die;

  my $orig;
  eval
  {
    die "No userid" unless(exists( $self->{userid} ));
    $orig = Schnuerpel::CGI::AdminUser->new('userid' => $self->{userid}); 
    $orig->do_select_by_userid();
  };
  my $r = $self->{error};
  if (defined($orig))
  {
    my $r_orig = $orig->{error};
    if (defined($r_orig) &&  $#$r_orig >= 0)
    {
      push @$r, @$r_orig;
      undef $orig;
    }
  }
  if ($@)
  {
    push @$r, $@;
    undef $orig;
  }
  return $orig;
}

######################################################################
sub do_change($$)
######################################################################
{
  my $self = shift || die;
  my $r_fields = shift || die;

  my $orig = $self->get_orig_user() || return 0;
  my $rc;
  eval
  {
     my $sql =
       "UPDATE r_user\n" .
       "SET ";
    my @bind;
    my $separator = '';
    for my $field( @$r_fields )
    {
      my $compare = $self->compare_field($orig, $field);
      next if ($compare == 0);
      $sql .= $separator;
      $sql .= $field;
      if ($compare == 1)
      {
	$sql .= ' = ?';
	push @bind, $self->{$field};
      }
      else
      {
	$sql .= ' = null';
      }
      $separator = ",\n";
    }

    die "Nothing to do" if (length($separator) == 0);
    push @bind, $self->{userid};
    $sql .= "\nWHERE id = ?\n";

    my $r = $self->{error};
    # push @$r, $sql;

    $rc = $self->db_execute($sql, \@bind, 1);
    if (defined($rc))
    {
      my $adminid = $self->{admin}->{adminid} || die;
      my $sql =
        "INSERT INTO r_user_change(\n" .
        "  admin, user, time\n" .
	") VALUES(?, ?, UNIX_TIMESTAMP())\n";
      # push @$r, $sql;
      $rc = $self->db_execute($sql, [ $adminid, $self->{userid} ], 1);
      my $errstr = $self->{DBC}->errstr();
      if (defined($errstr) && length($errstr) > 0)
        { push @$r, $errstr; }
    }
  };
  if ($@)
  {
    my $r = $self->{error};
    push @$r, $@;
    return 0;
  }
  return defined($rc);
}

######################################################################
sub do_change_password($)
######################################################################
{
  my $self = shift || die;

  my $orig = $self->get_orig_user() || return 0;
  my $rc = undef;
  eval
  {
    my $compare = $self->compare_field($orig, 'passwd_plain');
    die "Nothing to do" if ($compare != 1);
    $self->crypt_password();
    
     my $sql =
       "UPDATE r_user\n" .
       "SET passwd_plain = ?,\n" .
       "passwd_ht = ?\n" .
       "WHERE id = ?\n";
    my @bind = (
      $self->{passwd_plain}, $self->{passwd_ht}, $self->{userid}
    );
    $rc = $self->db_execute($sql, \@bind, 1);
  };
  if ($@)
  {
    my $r = $self->{error};
    push @$r, $@;
    return 0;
  }
  return defined($rc);
}

######################################################################
sub on_confirm_add($)
######################################################################
{
  my $self = shift() || die;

  if ($self->do_add() && $self->do_select_by_username())
  {
    $self->do_add_features();
    return $self->on_cancel( defined(CGI::param('send_email')) );
  }
  else
  {
    return $self->on_add();
  }
}

######################################################################
sub on_confirm_change($)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;

  # unconditionally erasing and setting features is a wild hack
  my $sql =
    "DELETE FROM r_feature\n" .
    "WHERE user = ?";
  $self->db_execute($sql, [ $self->{userid} ], undef);
  $self->do_add_features();

  my $ok = $self->do_change([
    'username', 'first_name', 'last_name', 'email',
    'sex', 'language', 'status'
  ]);
  if ($ok)
  {
    return $self->on_cancel( defined(CGI::param('send_email')) );
  }
  else
  {
    return $self->on_change();
  }
}

######################################################################
sub on_confirm_password($)
######################################################################
{
  my $self = shift() || die;
  my $cmd = shift;

  if ( $self->do_change_password() )
  {
    return $self->on_email();
  }
  else
  {
    return $self->on_password();
  }
}

######################################################################
sub on_cancel($)
######################################################################
{
  my $self = shift || die;
  my $send_email = shift;

  return $self->on_email() if ($send_email);
  return 'AdminTable';

#  my $target = 'admin.cgi?table=r_user&lang=' . $self->{lang};
#  if (exists( $self->{userid} ))
#    { $target .= '&r_user=' . $self->{userid}; }
#  print CGI::redirect($target);
#  close STDOUT;
#  exit(0);
}

######################################################################
sub on_email()
######################################################################
{
  my $self = shift || die;

  $self->{cmd} = CMD_MAIL;
  $self->get_user_data([ 'userid' ]) || die;
  $self->print_header();

  my %word = (
    'de' => [
      'schrieb',
      'Username',
      'Passwort',
      'Server',
      'FAQ     : http://albasani.net/wiki/FAQ' . "\n" .
      'Konfiguration: http://albasani.net/wiki/Category:Newsreader' . "\n" .
      "\n" .
      "Viel Spaß.\n",
    ],
    'en' => [
      'wrote',
      'Username',
      'Password',
      'Server',
      'FAQ     : http://albasani.net/wiki/FAQ_%28English%29' . "\n" .
      'Config  : http://albasani.net/wiki/Category:Newsreader' . "\n" .
      "\n" .
      "Have fun.\n"
    ],
  );

  my $r = $word{ $self->{language} } || die;

  # Note: Empty fields are stored as empty strings.
  # Thus join() would produce leading white space.
  # No advantage to simply concatenating.

  my $body = $self->{first_name} . ' ' . $self->{last_name};
  $body =~ s/^\s+//;
  $body = $self->{username} if (length($body) == 0);

  $body .= sprintf(" %s:\n\n", $r->[0]);
  $body .= sprintf("%-8s: %s\n", $r->[1], $self->{username});
  $body .= sprintf("%-8s: %s\n", $r->[2], $self->{passwd_plain});
  $body .= sprintf("%-8s: %s\n", $r->[3], 'reader.albasani.net');
  $body .= $r->[4];

  $self->{to} = $self->{username};

  $self->set_mail_form( $body );
  print $self->get_file('admin/user/mail.html');
  return $self->print_footer();
}

######################################################################
sub main()
######################################################################
{
  my $self = shift || die;

  my $admin = Schnuerpel::CGI::AdminMgr->new( $self );
  $admin->setLastLogin(); # modifies $self->{error}
  $self->{admin} = $admin;

  my $userid = $self->get_param('userid', GET_PARAM_INT);
  my $cmd = $self->{cmd} = $self->get_command($userid);

  if ($cmd == CMD_CANCEL)
    { return $self->on_cancel(0); }

  die unless(exists( $self->{lang} ));
  die unless(exists( $TITLE{ $self->{lang} } ));
  die unless(exists( $TITLE{ $self->{lang} }->[$cmd] ));
  $self->{title} = $TITLE{ $self->{lang} }->[$cmd];
  $self->get_user_param();

  my $func = $BUTTON_DEF[$cmd];
  die unless(defined($func));
  return $self->$func();
}

######################################################################
1;
######################################################################
