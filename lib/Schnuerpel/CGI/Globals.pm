package Schnuerpel::CGI::Globals;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  $DB_DATABASE
  $DB_PASSWD
  $DB_USER
  $CSS_URL
  getenv
  init
  @LANG
  %LANG
  $LANG_DIR
  module_loop
  $PICTURE_URL
  $SCRIPT_DIR
  $SERVER_NAME
  $SSI_DIR
);

use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser confess );

use warnings;
use Sys::Syslog;

######################################################################
# Variables
######################################################################

our $DB_DATABASE;
our $DB_PASSWD;
our $DB_USER;
our $CSS_URL;
our @LANG;
our %LANG;
our $LANG_DIR;
our $PICTURE_URL;
our $SCRIPT_DIR;
our $SCHNUERPEL_DIR;
our $SERVER_NAME;
our $SSI_DIR;

######################################################################
sub getenv($)
######################################################################
{
  my $var = shift || confess;

  my $value = $ENV{$var};
  return $value if ($value);
  die "Environment variable '$var' is not defined.";
}

######################################################################
sub getenvdir($)
######################################################################
{
  my $var = shift || confess;

  my $dir = getenv($var);
  return $dir if (-d $dir);
  die "Environment variable '$var' points to a directory that does not exist.";
}

######################################################################
sub init()
######################################################################
{
  $PICTURE_URL = getenv('R_PICTURE_URL');
  $SCHNUERPEL_DIR = getenvdir('SCHNUERPEL_DIR');
  $SERVER_NAME = getenv('SERVER_NAME');
  $SSI_DIR = $ENV{'R_SSI_DIR'} || $SCHNUERPEL_DIR . '/etc/cgi/ssi';
  $CSS_URL = $ENV{'R_CSS_URL'} || $SCHNUERPEL_DIR . '/etc/cgi/css/schnuerpel.css';

  $SCRIPT_DIR = $SCHNUERPEL_DIR . '/lib';
  $LANG_DIR = $ENV{'R_LANG_DIR'} || $SCHNUERPEL_DIR . '/etc/cgi';

  opendir(DIR, $LANG_DIR) || die "opendir $LANG_DIR: $!";
  for my $lang( grep { /^\w\w$/ && -d "$LANG_DIR/$_" } readdir(DIR) )
  {
    $LANG{$lang} = undef;
    push @LANG, $lang;
  }
  closedir(DIR);

  $DB_DATABASE = getenv('DB_DATABASE');
  $DB_USER = getenv('DB_USER');
  $DB_PASSWD = getenv('DB_PASSWD');
}

######################################################################
sub load_and_create($)
######################################################################
{
  my $view = shift || confess 'No $view';

  # set $module to __PACKAGE__ is "Schnuerpel::CGI::Globals"
  my $module = __PACKAGE__;

  # reduce to "Schnuerpel::CGI"
  $module =~ s#::[^:]+$##g;

  # extend to "Schnuerpel::CGI::Contact"
  $module .= '::' . $view;

  eval "use $module;";
  my $error = $@; # copy $@ of is required for syslog 
  if (!$error)
  {
    my $stmt = $module . '->new();';
    syslog('LOG_INFO', "load_and_create %s", $stmt);
    # no strict;
    my $new = eval $stmt;
    $error = $@;
    if (!$error)
    {
      return $new if ($new);
      syslog('LOG_ERR', 'load_and_create %s: returned undef', $stmt);
      return undef;
    }
  }

  syslog('LOG_ERR', 'load_and_create %s failed: %s', $module, $error);
  return undef;
}

######################################################################
sub module_loop(;$)
######################################################################
{
  binmode(STDIN, ":utf8");
  binmode(STDOUT, ":utf8");

  my $view = CGI::param('view');
  if (!$view)
  {
    $view = shift;
    if (!$view)
    {
      $view = getenv('SCRIPT_NAME');
      $view =~ s#^.*/##;
      $view =~ s#\.[^.]*$##;
      $view = ucfirst($view);
      if (!$view)
      {
        die 'Neither CGI parameter "view" nor parameter 1 defined.';
      }
    }
  }

  push @INC, $SCRIPT_DIR;

  do
  {
    CGI::param('view', $view);
    Sys::Syslog::openlog($view, '', 'local0');
    syslog('LOG_INFO', 'module_loop %s', CGI::param('view'));

    # my $m = $view->new();
    my $m = load_and_create($view);
    return if (!$m);

    $view = eval { $m->main(); };
    $m->done($@);
    Sys::Syslog::closelog();
  }
  while(defined($view));
}

######################################################################
1;
######################################################################
