package Schnuerpel::CGI::Contact;
use base qw( Schnuerpel::CGI::UserMgr );
@EXPORT_OK = qw( new );
use strict;
use encoding 'utf8';

use Carp qw( confess );
use CGI( -utf8 );
use Mail::Sendmail();
use Sys::Syslog qw();
use Schnuerpel::CGI::UserMgr qw();

######################################################################
sub new($@)
######################################################################
{
  my $proto = shift;

  my $class = ref($proto) || $proto || confess "Can't determine class";
  my ( %self ) = @_;
  my $self = \%self;

  bless($self, $class);
  Schnuerpel::CGI::UserMgr::init($self);

  $self->get_param('name', undef);
  $self->get_param('from', undef);
  $self->get_param('subject', undef);
  $self->get_param('body', undef);

  $self->{hidden_list} = [
    'lang', 'name', 'from', 'subject', 'body'
  ];

  return $self;
}

######################################################################
sub showForm()
######################################################################
{
  my $self = shift;
}

######################################################################
sub send()
######################################################################
{
  my $self = shift || confess;

  my $name = $self->{name};
  $name =~ s#[\r\n\s]+$##;

  my $from = $self->{from};
  $from =~ s#[\r\n\s]+$##;
  $from = $name . ' <' . $from . '>';

  my $subject = $self->{subject};
  $subject =~ s#[\r\n\s]+$##;

  my $to = $self->get_file('contact-mail.txt');
  $to =~ s#[\r\n\s]+$##;

  my %mail = (
    'From' => $from,
    'To' => $to,
    'Subject' => $subject,
    'Message' =>
      $self->{body} . "\n\n-- \n" .
      $self->{lang} . "\n" . 
      $ENV{REMOTE_ADDR} . "\n" . 
      $ENV{HTTP_USER_AGENT}
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
    return $self->print_error('contact-mail');
  }

  $self->print_header();
  print $self->get_file('contact.mail-sent.html');
  $self->print_footer();
}

######################################################################
sub main()
######################################################################
{
  my $self = shift || confess;
  if (CGI::param('Cancel'))
  {
    print CGI::redirect('/');
    return;
  }

  if (CGI::param('send'))
  {
    $self->send();
  }
  else
  { 
    $self->set_mail_form( $self->{body} );
    $self->print_header(1);
    print $self->get_file('contact.html');

    if (0) {
      printf
	'<p><small><tt>' .
	'MOD_PERL=%s MOD_PERL_API_VERSION=%s CONTENT_TYPE=%s' .
	'</tt></small></p>' . "\n",
	$ENV{MOD_PERL},
	$ENV{MOD_PERL_API_VERSION},
	$ENV{'CONTENT_TYPE'};
    }
    $self->print_footer();
  }
}

######################################################################
1;
######################################################################
