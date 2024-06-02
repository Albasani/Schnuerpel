package Schnuerpel::CGI::Register;
use base qw( Schnuerpel::CGI::UserMgr );
my @EXPORT_OK = qw( new );

use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

use Authen::Captcha();
use Digest::MD5();
use Mail::Sendmail();
use Schnuerpel::CGI::Globals qw(
  $SCRIPT_DIR
);
use Schnuerpel::CGI::UserMgr qw(
  $SERVER_NAME
  $SSI_DIR
);

######################################################################

# maximum number of connections within TIMESLOT_REGISTER seconds
use constant MAX_CONNECTIONS_IN_TIMESLOT => 60;

use constant CAPTCHA_LENGTH => 5;
use constant CAPTCHA_WIDTH => 64;
use constant CAPTCHA_HEIGHT => 48;
use constant CAPTCHA_OUT_DIR => 'captcha-out';
use constant CAPTCHA_DATA_DIR => 'captcha-data';

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

  $self->{'captcha_out_dir'} = $ENV{'R_CAPTCHA_OUT_DIR'} ||
    $SCRIPT_DIR . '/' . CAPTCHA_OUT_DIR;
  $self->{'captcha_data_dir'} = $ENV{'R_CAPTCHA_DATA_DIR'} ||
    $SCRIPT_DIR . '/' . CAPTCHA_DATA_DIR,;

  $self->get_user_param();
  $self->get_param('session_hash', '\W');
  $self->get_param('captcha_response', '\W');

  $self->{hidden_list} = [ 'lang', 'session_hash', 'username',
    'sex', 'first_name', 'last_name', 'captcha_response' ];

  return $self;
}

######################################################################
sub get_new_hash()
#######################################################################
{
  my $self = shift;

  my $time = $self->db_delete_timeslot('r_remote_address');

  my $str = $self->{REMOTE_ADDR} . time() . rand();
  my $file = '/proc/uptime';
  open(FILE, '<', $file) || die "$!: $file";
  { local $/; $str .= <FILE>; }
  close(FILE);
  my $hash = Digest::MD5::md5_hex($str);

  die 'No "DBC" in $self' unless( $self->{DBC} );

  my $sql =
    "SELECT count(*)\n" .
    "FROM r_remote_address\n";
  my $row = $self->{DBC}->selectrow_arrayref($sql, undef);
  if (!defined($row) ||
      $#$row != 0 ||
      $row->[0] > MAX_CONNECTIONS_IN_TIMESLOT)
  {
    $self->{DBC}->commit() || die "commit " . $self->{DBC}->errstr();
    return undef;
  }

  $sql =
    "INSERT INTO r_remote_address(session_hash, address, timeslot)\n" .
    "VALUES(?, ?, ?)";
  $self->db_execute($sql, [ $hash, $self->{REMOTE_ADDR}, $time ]);
  return $hash;
}

######################################################################
sub verify_hash($$)
#######################################################################
{
  my $self = shift;

  my $sql =
    "SELECT timeslot, captcha_hash\n" .
    "FROM r_remote_address\n" .
    "WHERE session_hash = ?\n" .
    "AND address = ?\n";
  my $row = $self->db_select_row($sql,
    [ $self->{session_hash}, $self->{REMOTE_ADDR} ]
  );
  return 0 unless(defined($row) && $row->[0] > 0);
  $self->{captcha_challenge} = $row->[1];
  return 1;
}

######################################################################
sub show_terms_of_use()
######################################################################
{
  my $self = shift;
  die unless(defined($self));

  $self->{session_hash} = $self->get_new_hash();
  unless(exists( $self->{session_hash} ))
  {
    $self->print_error("too_many_connections");
    return;
  }

  $self->{TERMS_OF_USE}
  = $self->get_file("terms_of_use.html.$self->{lang}", $SSI_DIR);

  $self->print_header(1);
  print $self->get_file('intro.html');
  $self->print_footer();
}

######################################################################
sub new_captcha($)
######################################################################
{
  my $self = shift || die;

  return Authen::Captcha->new(
    data_folder => $self->{'captcha_data_dir'},
    output_folder => $self->{'captcha_out_dir'},
    height => CAPTCHA_HEIGHT,
    width => CAPTCHA_WIDTH
  );
}

######################################################################
sub db_update_captcha($)
######################################################################
{
  my $self = shift;
  my $captcha_challenge = shift;

  my $sql =
    "UPDATE r_remote_address\n" .
    "SET captcha_hash = ?, timeslot = ?\n" .
    "WHERE session_hash = ?\n" .
    "AND address = ?\n";
  my @bind = (
    $captcha_challenge, time(), $self->{session_hash},
    $self->{REMOTE_ADDR}
  );
  return $self->db_execute($sql, \@bind, 1);
}

######################################################################
sub show_captcha($)
######################################################################
{
  my $self = shift;
  my $captcha_challenge = shift;

  my $captcha = $self->new_captcha();
  if (!defined($captcha_challenge))
  {
    $captcha_challenge = $captcha->generate_code(CAPTCHA_LENGTH);
    $self->db_update_captcha($captcha_challenge);
  }
  $self->print_header(1);
  $self->set_user_form();

  $self->{INPUT_IMG} = CGI::img({
    -src => CAPTCHA_OUT_DIR . '/' . $captcha_challenge . '.png',
    -alt => 'Captcha'
  });
  $self->{INPUT_RESPONSE} = CGI::textfield(
    -name => 'captcha_response',
    -size => 64,
    -value => $self->{captcha_response}
  );

  print $self->get_file('captcha.html');
  $self->print_footer();
}

######################################################################
sub show_captcha_response()
######################################################################
{
  my $self = shift;

  my $captcha = $self->new_captcha();
  my $results = $captcha->check_code(
    $self->{captcha_response},
    $self->{captcha_challenge}
  );
  $self->{CAPTCHA_RESULTS} = $results;

  #  1 : Passed
  #  0 : Code not checked (file error)
  # -1 : Failed: code expired
  # -2 : Failed: invalid code (not in database)
  # -3 : Failed: invalid code (code does not match crypt)
  
  if ($results <= -3)
    { return $self->print_error('captcha-wrong'); }
  if ($results != 1)
    { return $self->print_error('captcha-internal'); }

  $self->db_update_captcha(undef);
  my $hash = $self->db_insert_confirm();
    
  my $url = "http://$SERVER_NAME$self->{SCRIPT_NAME}";
  $url =~ s#[^/]*$##;
  $url .= 'confirm.cgi?hash=';
  $url .= $hash;

  my $to = $self->{username};
  my $name = join(' ', $self->{first_name}, $self->{last_name});
  $to = $name . " <$to>" if (length($name) > 0);

  my $from = $self->get_file('mail.from.txt');
  $from =~ s#[\r\n\s]+$##;

  my $subject = $self->get_file('mail.subject.txt');
  $subject =~ s#[\r\n\s]+$##;

  $self->{CONFIRM_LINK} = $url;
  my %mail = (
    'From' => $from,
    'To' => $to,
    'Subject' => $subject,
    'Message' => $self->get_file('mail.txt')
  );
  my $ok = Mail::Sendmail::sendmail(%mail);

  $self->{MAIL_HEADER} = sprintf(
    "<pre>From:    %s\n" .
    "To:      %s\n" .
    "Subject: %s</pre>\n",
    CGI::escapeHTML($from),
    CGI::escapeHTML($to),
    CGI::escapeHTML($subject)
  );

  if (!$ok)
  {
    $self->{MAIL_LOG} = sprintf(
      "<pre>%s\n%s</pre>\n",
      CGI::escapeHTML($Mail::Sendmail::log),
      CGI::escapeHTML($Mail::Sendmail::error)
    );
    return $self->print_error('register-mail');
  }

  $self->print_header();
  print $self->get_file('mail-sent.html');
  $self->print_footer();
}

######################################################################
sub main()
######################################################################
{
  my $self = shift;

  if (CGI::param('Cancel'))
  {
    print CGI::redirect('/');
    return;
  }

  return $self->show_terms_of_use()
  unless(exists( $self->{session_hash} ));

  return $self->print_error('session_key')
  unless( $self->verify_hash() );

  return $self->show_captcha(undef)
  if (CGI::param('TermsOfUseAgree') || CGI::param('CaptchaRetry'));

  return $self->show_terms_of_use()
  unless(exists( $self->{captcha_challenge} ));

  return $self->show_captcha_response()
  if ( defined(CGI::param('CaptchaSubmit')) );

  return $self->show_captcha( $self->{captcha_challenge} );
}

######################################################################
1;
######################################################################
