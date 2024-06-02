package Schnuerpel::CGI::UserMgr;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  &DEBUG_SQL
  &GET_PARAM_DATE
  &GET_PARAM_EMAIL
  &GET_PARAM_INT
  &GET_PARAM_LANG
  &GET_PARAM_PASSWORD
  &LANG_DEFAULT
  &MYSQL_ON_DUPLICATE
  &new
  &save
  $SERVER_NAME
  $SSI_DIR
);

use strict;
use encoding 'utf8';
use Carp qw( confess );
use CGI( -utf8 );
use DBI();
use I18N::AcceptLanguage();
use Sys::Syslog qw();
use Schnuerpel::CGI::Globals qw(
  $DB_DATABASE
  $DB_PASSWD
  $DB_USER
  $CSS_URL
  getenv
  @LANG
  %LANG
  $LANG_DIR
  $PICTURE_URL
  $SCRIPT_DIR
  $SSI_DIR
);

######################################################################

our %PRINT_FILE;

######################################################################

use constant DEBUG_SQL => 0;
use constant DEBUG_PARAM => 0;
use constant DEBUG_EXPR => 0;

# "ON DUPLICATE KEY UPDATE" was added in MySQL 4.1.0
use constant MYSQL_ON_DUPLICATE => 1;

######################################################################
# use constant CHARSET => 'ISO-8859-1';
use constant CHARSET => 'utf-8';
use constant LANG_DEFAULT => 'de';

use constant TIMESLOT_CONFIRM => 60 * 60 * 24;
use constant TIMESLOT_REGISTER => 60 * 30;

my %TABLE_TIMESLOT = (
  'r_remote_address' => TIMESLOT_REGISTER,
  'r_confirm' => TIMESLOT_CONFIRM,
);

# use constant GET_PARAM_EMAIL => '[^\w@.\(\)<>+-]';
use constant GET_PARAM_EMAIL => '[^ ^\w@\(\)<>.!#$%&*/=?^_{|}~`\'+-]';
use constant GET_PARAM_SEX => '[^fm\-]';

# does not work with special characters like &uuml;
# use constant GET_PARAM_NAME => '[^\w\.\- ]';

use constant GET_PARAM_LANG => '[^a-z]';
use constant GET_PARAM_PASSWORD => '[^[:alnum:] \'/$@=:+-]';
use constant GET_PARAM_INT => '[^\d+-]';
use constant GET_PARAM_DATE => '[^\d :-]';

use constant MAIL_STYLE => 'font-family:monospace';

######################################################################
sub get_param($$;$$)
######################################################################
{
  my $self = shift || die;
  my $name = shift || die;
  my $pattern = shift;
  my $r_hash = shift;

  if (DEBUG_PARAM)
  {
    Sys::Syslog::syslog('info',
      'UserMgr::get_param name=[%s](%d) r_hash=%d',
      $name, exists( $self->{$name} ), defined($r_hash)
    );
  }
  if (exists( $self->{$name} ))
  {
    my $value = $self->{$name} || die;
    return $value;
  }
  if (my @param = CGI::param($name))
  {
    my $value = pop(@param);
    $value =~ s#[\r\n\s]+$##;
    if (defined($pattern))
    {
      $value =~ s#$pattern##g;
    }

    # If argument $r_hash is defined we check whether value is valid.
    # Otherwise there is no check.
    if (!defined($r_hash) || exists($r_hash->{$value}))
    {
      if (DEBUG_PARAM)
      {
	Sys::Syslog::syslog('info',
	  'UserMgr::get_param [%s]=>[%s]',
	  $name, $value
	);
      }
      return $self->{$name} = $value;
    }
  }

  return undef;
}

######################################################################
sub set_lang(;$)
######################################################################
{
  my $self = shift || confess;
  my $lang = shift;

  if (!defined($lang) || !exists($LANG{ $lang }))
  {
    $lang = $self->get_param('lang', GET_PARAM_LANG, \%LANG);
    if (!defined($lang))
    {
      my $acceptor = I18N::AcceptLanguage->new();
      $lang = $acceptor->accepts($ENV{HTTP_ACCEPT_LANGUAGE}, \@LANG);
      if (!defined($lang) || !exists($LANG{ $lang }))
	{ $lang =  LANG_DEFAULT; }
    }
  }
  $self->{lang} = $lang || confess;
  confess '$LANG_DIR is not defined.' if (!$LANG_DIR);
  $self->{LANG_DIR} = $LANG_DIR . '/' . $self->{lang};
  unless(-d $self->{LANG_DIR})
  {
    confess 'Directory does not exist: ' . $self->{LANG_DIR};
  }
  return $lang;
}

######################################################################
sub connect_db($)
######################################################################
{
  my Schnuerpel::CGI::UserMgr $self = shift || confess;

  my $dbc = DBI->connect($DB_DATABASE, $DB_USER, $DB_PASSWD,
    { PrintError => 1, AutoCommit => 0, mysql_enable_utf8 => 1 }
  );
  unless(defined( $dbc ))
    { die "DBI->connect failed.\n$DBI::errstr"; }
  unless($dbc->{mysql_enable_utf8})
    { die "DBI->connect could not set mysql_enable_utf8"; }
  $dbc->ping();
  
  $self->{DBC} = $dbc;
}

######################################################################
sub init($;$)
######################################################################
{
  my Schnuerpel::CGI::UserMgr $self = shift || confess;
  my $lang = shift;

  eval
  {
    Schnuerpel::CGI::Globals::init() unless(defined($SCRIPT_DIR));
    $self->{BASE_LOGO} = 'logo_small.gif';
    $self->{CSS_URL} = $CSS_URL;
    $self->set_lang($lang);

    $self->{REMOTE_ADDR} = getenv('REMOTE_ADDR');

    # HTTP_HOST includes port number
    $self->{HTTP_HOST} = getenv('HTTP_HOST');

    # SERVER_NAME is the plain host name
    $self->{SERVER_NAME} = getenv('SERVER_NAME');
    
    my $base_name = $self->{view} = CGI::param('view');
    if (!$base_name)
    {
      $base_name = getenv('SCRIPT_NAME');
      $base_name =~ s#\.[^\.]*$##;
      $base_name =~ s#^.*/##;
      if (!$base_name)
      {
        die 'Neither CGI parameter "view" nor environment ' .
	  'variable "SCRIPT_NAME" set.';
      }
    }
    $self->{base_name} = $base_name;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
    = localtime(time); 
    $self->{LAST_MODIFIED} = sprintf("%04d-%02d-%02d %02d:%02d",
      $year + 1900, $mon + 1, $mday, $hour, $min);

    if ($DB_DATABASE) { $self->connect_db(); }
  };
  if ($@)
  {
    $self->{EXCEPTION_MSG} = $@;
    $self->print_error('exception');
    exit;
  }
}

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
sub done($)
######################################################################
{
  my $self = shift || die;
  my $msg = shift;

  if ($self->{DBC})
  {
    $self->{DBC}->rollback();
    $self->{DBC}->disconnect();
    $self->{DBC} = undef;
  }
  if ($msg)
  {
    $self->{EXCEPTION_MSG} = $msg;
    $self->print_error('exception');
  }
  Sys::Syslog::closelog();
}

######################################################################
sub eval_expr($;$)
######################################################################
{
  my $self = shift || die;
  my $expr = shift;

  if (DEBUG_EXPR)
    { Sys::Syslog::syslog('info', 'eval_expr a=[%s]', $expr); }

  #
  # substitute variables
  #
  $expr =~ s@\${(\w+)}@
    exists( $self->{$1} ) ? $self->{$1} : '';
  @egsx;

  if (DEBUG_EXPR)
    { Sys::Syslog::syslog('info', 'eval_expr b=[%s]', $expr); }

  #
  # operator "!" checks for empty string
  # return 0 if still non-white space left
  #
  $expr =~ s@!\s*(\S+)@0@gs;

  if (DEBUG_EXPR)
    { Sys::Syslog::syslog('info', 'eval_expr c=[%s]', $expr); }

  #
  # pattern matching, check whether string starts with another string
  #

  $expr =~ s@(\S*)\s*==?\s*/(\S*)/@
    $1 =~ m/$2/ ? 1 : 0
  @egsx;

  if (DEBUG_EXPR)
    { Sys::Syslog::syslog('info', 'eval_expr d=[%s]', $expr); }

  # simple string comparison with operator "=" or "=="
  # variable expansion may yield the empty string,
  # so match (\S*) instead of (\S+)

  $expr =~ s@(\S*)\s*==?\s*(\S*)@
    $1 eq $2 ? 1 : 0
  @egsx;

  if (DEBUG_EXPR)
    { Sys::Syslog::syslog('info', 'eval_expr e=[%s]', $expr); }

  return $expr;
}

######################################################################
sub get_file($;$)
######################################################################
{
  my $self = shift || die;
  my $file = shift || die;
  my $dir = shift;

  unless(defined($dir))
  {
    $dir = $self->{LANG_DIR} || confess;
  }
  my $path = $dir . '/' . $file;
  my $contents = $PRINT_FILE{$path};
  unless(defined($contents))
  {
    open(FILE, '<:utf8', $path) || die "$!: $path";
    { local $/; $PRINT_FILE{$path} = $contents = <FILE>; }
    close(FILE);
  }

  # ------------------------------------------------------------------
  # if statements
  # ------------------------------------------------------------------
  while($contents =~ m@
    (.*?)
    <!--\#if\s+expr="([^"]*)"\s*-->
    (.*?)
    <!--\#endif\s*-->
    (.*)$
  @sx)
  {
    my ( $prefix, $expr, $body, $suffix ) = ( $1, $2, $3, $4 );
    $body = '' unless( $self->eval_expr($expr) );
    $contents = $prefix . $body .$suffix;
  }

  # ------------------------------------------------------------------
  # include statements
  # ------------------------------------------------------------------
  while($contents =~ m@
    (.*?)
    <!--\#include\s+virtual="([^"]*)"\s*-->
    (.*)$
  @sx)
  {
    my ( $prefix, $path, $suffix ) = ( $1, $2, $3 );
    $path =~ m@(.*/)([^/]*)$@;
    $contents =
      $prefix .
      $self->get_file($2, $ENV{'DOCUMENT_ROOT'} . $1) .
      $suffix;
  }

  # ------------------------------------------------------------------
  # echo statements
  # ------------------------------------------------------------------
  $contents =~ s@<!--\#echo\s+var=(['"])(\w+)\1\s*-->@
    exists( $self->{$2} ) ? $self->{$2} : '';
  @egsx;

  return $contents;
}

######################################################################
sub print_hidden($;$)
######################################################################
{
  my $self = shift || die;
  my $var = shift;
  my $hidden = shift;
  $hidden = $var unless(defined($hidden));

  if (exists( $self->{$var} ))
  {
    my $val = $self->{$var};
    if (defined($val) && length($val) > 0)
    {
      CGI::param($hidden, $val);
      print CGI::hidden(
        -id => 'hidden_' . $hidden,
	-name => $hidden,
	-default => $val
      ), "\n";
    }
  }
  else
  {
    CGI::param(
      -id => 'hidden_' . $hidden,
      -name => $hidden
    );
  }
}

######################################################################
sub print_start_form($;$)
######################################################################
{
  my $self = shift || die;
  my $action = shift;

  $action = $ENV{SCRIPT_NAME} unless(defined($action));

  print
    '<form action="',
    $action,
    '" method="post" enctype="multipart/form-data" accept-charset="',
    CHARSET,
    '">',
    "\n";

  # Hidden fields come before any real input elements that
  # override them.

  my $hidden_list = $self->{hidden_list};
  if (defined( $hidden_list ))
  {
    print "<fieldset style=\"display:none\">\n";
    printf "<!-- %s -->\n", join(", ", @$hidden_list);
    for my $var( @$hidden_list )
      { $self->print_hidden($var); }
    print "</fieldset>\n";
  }
}

######################################################################
sub print_header($;$)
######################################################################
{
  my $self = shift || die;
  my $showLanguages = shift;

  if (!exists( $self->{lang} ))
    { $self->set_lang(); }
  {
    my $lang = $self->{'lang'} || die 'No "lang" in $self';
    my $base_name = $self->{'base_name'} || die 'No "base_name" in $self';
    print
      CGI::header(
	-charset => CHARSET
      ),
      $self->get_file('doctype.html.' . $lang, $SSI_DIR),
      $self->get_file('title.' . $base_name . '.html'),
      $self->get_file('header.html.' . $lang, $SSI_DIR);
  }
  $self->print_start_form();

  if (defined($showLanguages))
  {
    print '<div id="languages" class="languages">',
          '<div class="inset">', "\n";
    for my $lang(sort keys %LANG)
    {
      print CGI::image_button(
	-name => 'lang',
	-value => $lang,
	-src => "$PICTURE_URL/$lang.gif",
	-alt => $lang
      ),
      "\n"
    }
    print '</div></div>', "\n";
  }

  print '<div id="content">', "\n";
}

######################################################################
sub print_footer()
######################################################################
{
  my $self = shift || die;

  print
    "</div><!-- content -->\n",
    CGI::end_form(),
    $self->get_file("footer.html." . $self->{lang}, $SSI_DIR);

  # 2007-03-03
  return undef;
}

######################################################################
sub print_error($$)
######################################################################
{
  my $self = shift || die;
  my $name = shift || die;

  eval # catch errors during initialization
  {
    $self->print_header();
    print $self->get_file("error.$name.html");
    $self->print_footer();
  };
  if ($@) { die $name . ': ' . $self->{EXCEPTION_MSG}; }
}

######################################################################
sub db_execute($$$;$)
######################################################################
{
  my $self = shift || die;
  my $sql = shift || die;
  my $r_bind = shift || die;
  my $expected = shift;

  my $rc;
  eval
  {
    my $dbc = $self->{DBC} || confess 'No "DBC" in $self';
    my $sth = $dbc->prepare($sql)
    || die "prepare\n" . $dbc->errstr() . ":\n" . $sql;

    if (DEBUG_SQL)
      { Sys::Syslog::syslog('info', '%s', $sql); }
    $rc = $sth->execute(@$r_bind)
    || die "execute\n" . $dbc->errstr() . ":\n" . $sql;
    $dbc->commit()
    || die "commit\n" . $dbc->errstr();
  };
  my $r = $self->{error};
  if ($@)
  {
    push @$r, $@;
    return undef;
  }
  if (defined($rc) && defined($expected) && $rc != $expected)
  {
    push @$r, "Affected $rc records instead of $expected";
    return undef;
  }
  return $rc;
}

######################################################################
sub db_select_row($$$)
######################################################################
{
  my $self = shift || die;
  my $sql = shift || die;
  my $r_bind = shift || die;

  my $row;
  eval
  {
    my $dbc = $self->{DBC} || die;
    if (DEBUG_SQL)
      { Sys::Syslog::syslog('info', '%s', $sql); }
    $row = $dbc->selectrow_arrayref($sql, undef, @$r_bind);
  };
  my $r = $self->{error};
  if ($@)
  {
    push @$r, $@;
    return undef;
  }
  return $row if (defined($row) && $#$row >= 0);
  push @$r, 'No data returned.';
  return undef;
}

######################################################################
sub db_select_all($$$)
######################################################################
{
  my $self = shift || die;
  my $sql = shift || die;
  my $r_bind = shift || die;

  my $rows;
  eval
  {
    my $dbc = $self->{DBC} || die;
    if (DEBUG_SQL)
      { Sys::Syslog::syslog('info', '%s', $sql); }
    $rows = $dbc->selectall_arrayref($sql, undef, @$r_bind);
  };
  my $r = $self->{error};
  if ($@)
  {
    push @$r, $@;
    return undef;
  }
  return $rows if (defined($rows) && $#$rows >= 0);
  push @$r, 'No data returned.';
  return undef;
}

######################################################################
sub db_delete_timeslot($$;$$)
######################################################################
{
  my $self = shift || die;
  my $table = shift || die;
  my $delta = shift;

  unless(defined($delta))
  {
    $delta = $TABLE_TIMESLOT{$table};
    unless(defined($delta))
    {
      die "No timeslot defined for table $table";
    }
  }

  my $time = time();
  my $sql =
    "DELETE FROM $table\n" .
    "WHERE timeslot < ?\n";
  $self->db_execute($sql, [ $time - $delta ]);
  return $time;
}

######################################################################
sub db_insert_confirm()
######################################################################
{
  my $self = shift || die;

  my $time = time();
  my $str = $self->{session_hash};
  $str .= '-';
  $str .= #time;
  $str .= '-';
  $str .= rand();
  my $hash = Digest::MD5::md5_hex($str);

  my $sql =
    "INSERT INTO r_confirm(confirm_hash, address,\n" .
    "timeslot, username, sex, first_name, last_name, language)\n" .
    "VALUES(?, ?, ?, ?, ?, ?, ?, ?)";
  my $sex = $self->{sex};
  my @bind = (
    $hash, $self->{REMOTE_ADDR}, $time, $self->{username},
    defined($sex) ? $sex : '-',
    $self->{first_name},
    $self->{last_name},
    $self->{lang}
  );
  $self->db_execute($sql, \@bind, 1);
  return $hash;
}

######################################################################
sub get_user_param()
######################################################################
{
  my $self = shift;

  my $username = $self->get_param('username');
  $self->get_param('sex', GET_PARAM_SEX);
  $self->get_param('first_name');
  $self->get_param('last_name');

  if ($username =~ m/^\s*([^<>]*)\s*<([^>]+@[^>]+)>\s*$/)
  {
    $username = $2;
    my @name = split(/\s+/, $1);
    my $last_name = pop(@name);
    if (defined($last_name))
    {
      $self->{last_name} = join(' ', $last_name, $self->{last_name});
    }
    $self->{first_name} = join(' ', @name, $self->{first_name});
  }

  my $pattern = GET_PARAM_EMAIL;
  $username =~ s#$pattern##g;
  $self->{username} = $username;
  $self->{first_name} =~ s#\s+$##;
  $self->{last_name} =~ s#\s+$##;
}

######################################################################
sub set_user_form($)
######################################################################
{
  my $self = shift;

  $self->{INPUT_USERNAME} = CGI::textfield(
    -id => 'input_username',
    -name => 'username',
    -size => 64,
    -value => $self->{username}
  );
  $self->{INPUT_FIRST} = CGI::textfield(
    -id => 'input_first_name',
    -name => 'first_name',
    -size => 64,
    -value => $self->{first_name}
  );
  $self->{INPUT_LAST} = CGI::textfield(
    -id => 'input_last_name',
    -name => 'last_name',
    -size => 64,
    -value => $self->{last_name}
  );

  $self->{sex} = '-' unless(exists( $self->{sex} ));
  $self->{INPUT_SEX_MALE} = $self->radio_button('sex', 'm');
  $self->{INPUT_SEX_FEMALE} = $self->radio_button('sex', 'f');
  $self->{INPUT_SEX_NA} = $self->radio_button('sex', '-');
}

######################################################################
sub set_mail_form($$)
######################################################################
{
  my $self = shift() || die;
  my $body = shift;

  my $name = exists($self->{name})
  ?  $self->{name}
  : join(' ', $self->{first_name}, $self->{last_name});
  $name =~ s/\s*$//;

  $self->{INPUT_NAME} = CGI::textfield(
    -name => 'name',
    -size => 64,
    -value => $name,
    -style => MAIL_STYLE
  );
  $self->{INPUT_FROM} = CGI::textfield(
    -name => 'from',
    -size => 64,
    -value => $self->{from},
    -style => MAIL_STYLE
  );
  $self->{INPUT_TO} = CGI::textfield(
    -name => 'to',
    -size => 64,
    -value => $self->{to},
    -style => MAIL_STYLE
  );
  $self->{INPUT_SUBJECT} = CGI::textfield(
    -name => 'subject',
    -size => 64,
    -value => $self->{subject},
    -style => MAIL_STYLE
  );
  $self->{INPUT_BODY} = CGI::textarea(
    -name => 'body',
    -columns => 64,
    -rows => 10,
    -default => $body,
    -style => MAIL_STYLE
  );
}

######################################################################
sub radio_button($$)
######################################################################
{
  my $self = shift || die;
  my $name = shift || die;
  my $value = shift; # empty string is valid, so no die

  my $result = "<input type=\"radio\" name=\"$name\" value=\"$value\"";
  if (exists($self->{$name}) && $self->{$name} eq $value)
    { $result .= ' checked="checked"'; }
  return $result . "/>\n";
}  

######################################################################
# sub module_loop($$)
######################################################################
# {
#   my $module = shift;
#   my $syslogIdent = shift;
# 
#   while(length($module) > 0)
#   {
#     Sys::Syslog::openlog($syslogIdent, '', 'local0');
#     require $module . '.pm';
#     my $c = $module->new();
#     $module = eval { $c->main(); };
#     $c->done($@);
#     Sys::Syslog::closelog();
#   }
# }

######################################################################
1;
######################################################################
