#! /usr/bin/perl -ws
use strict;
use Mail::Internet();

######################################################################
sub check_keep_header($;$)
######################################################################
{
  my $head = shift || die;
  my $keep_list = shift;

  my %keep_header = (
    'approved' => undef,
    'cancel-key' => undef,
    'cancel-lock' => undef,
    'content-transfer-encoding' => undef,
    'content-type' => undef,
    'date' => undef,
    'followup-to' => undef,
    'from' => undef,
    'lines' => undef,
    'message-id' => undef,
    'mime-version' => undef,
    'newsgroups' => undef,
    'references' => undef,
    'reply-to' => undef,
    'sender' => undef,
    'subject' => undef,
    'user-agent' => undef,
    'x-no-archive' => undef,
  );
  if ($keep_list)
  {
    for my $word( split(/,/, lc($keep_list)) )
    {
      $keep_header{$word} = undef;
    }
  }

  foreach my $tag ($head->tags())
  {
    if (!exists($keep_header{ lc($tag) }))
      { $head->delete($tag); }
  }
}

######################################################################
sub check_newsgroups($$)
######################################################################
{
  my $head = shift || die;
  my $dst = shift || die;

  my $newsgroups = $head->get('Newsgroups');
  if ($newsgroups)
  {
    my $found = grep { $_ eq $::DST; } split(/\s*,\s*/, $newsgroups);
    if ($found) { return 1; }
  }
  $head->replace('Newsgroups', $::DST);
  return 0;
}

######################################################################
sub check_one_header($$;$$$)
######################################################################
{
  my $head = shift || die;
  my $name = shift || die;
  my $replacement = shift;
  my $default = shift;
  my $is_required = shift;

  if ($replacement)
  {
    $head->replace($name, $replacement);
  }
  elsif ($head->get($name))
  {
    return;
  }
  elsif ($default)
  {
    $head->replace($name, $default);
  }
  elsif ($is_required)
  {
    die "No header '$name'.";
  }
}

######################################################################
# MAIN
######################################################################
die 'No -sDST' unless($::DST);
$::NNTPSERVER = undef unless($::NNTPSERVER);
$::REMOVE_SIG = undef unless($::REMOVE_SIG);

$::PUBLISH = undef unless($::PUBLISH);
$::KEEP_HEADER = $::PUBLISH unless($::KEEP_HEADER);

$::APPROVED = undef unless($::APPROVED);
$::REPLACE_APPROVED = $::APPROVED unless($::REPLACE_APPROVED);
$::DEFAULT_APPROVED = undef unless($::DEFAULT_APPROVED);

$::MAINTAINED = undef unless($::MAINTAINED);
$::REPLACE_MAINTAINED = $::MAINTAINED unless($::REPLACE_MAINTAINED);

$::FOLLOWUP = undef unless($::FOLLOWUP);
$::DEFAULT_FOLLOWUP = $::FOLLOWUP unless($::DEFAULT_FOLLOWUP);
$::REPLACE_FOLLOWUP = undef unless($::REPLACE_FOLLOWUP);

$::DEFAULT_SENDER = undef unless($::DEFAULT_SENDER);
$::REPLACE_SENDER = undef unless($::REPLACE_SENDER);

my $mail = new Mail::Internet(\*STDIN, FromMail => 'IGNORE');
my $head = $mail->head();

if ($::REMOVE_SIG) { $mail->remove_sig(); }
$mail->tidy_body();
$mail->sign(File => $ENV{HOME} . '/.Sig');

check_keep_header($head, $::KEEP_HEADER);
check_newsgroups($head, $::DST);
check_one_header($head, 'Approved',        $::REPLACE_APPROVED,   $::DEFAULT_APPROVED, 1);
check_one_header($head, 'Followup-To',     $::REPLACE_FOLLOWUP,   $::DEFAULT_FOLLOWUP   );
check_one_header($head, 'Sender',          $::REPLACE_SENDER,     $::DEFAULT_SENDER     );
check_one_header($head, 'X-Maintained-By', $::REPLACE_MAINTAINED                        );

if ($::NNTPSERVER)
{
  use Schnuerpel::ConfigNNTP();
  use Schnuerpel::NNTP();
  my $config = Schnuerpel::ConfigNNTP->new($::NNTPSERVER);
  my $r_nntp = Schnuerpel::NNTP::connect(undef, $config);
  $mail->nntppost(Host => $r_nntp->{'nntp'});
}
else
{
  $head->add('Path', 'not-for-mail');
  $mail->print(\*STDOUT);
}
