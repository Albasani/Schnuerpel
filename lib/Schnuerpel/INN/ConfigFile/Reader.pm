######################################################################
#
# $Id: Reader.pm 510 2011-07-20 13:56:21Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

package Schnuerpel::INN::ConfigFile::Reader;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
  $new
);
use strict;

# use Carp qw( confess );
# use Data::Dumper;

######################################################################
sub new($;$)
######################################################################
{
  my $proto = shift;
  my $delegate = shift;

  my $class = ref($proto) || $proto;
  my $self  = { delegate => $delegate };
  bless($self, $class);

  return $self;
}

######################################################################
sub open($$)
######################################################################
{
  my $self = shift || die;
  my $filename = shift;

  $self->close();
  if ($filename)
  {
    my $file;
    open($file, '<', $filename) || die "Can't open file $filename: $!";
    $self->{filename} = $filename;
    $self->{file} = $file;
  }
}

######################################################################
sub close($)
######################################################################
{
  my $self = shift || die;
  delete $self->{filename};
  delete $self->{file};
  delete $self->{line};
  delete $self->{token};
  $self->{line_nr} = 0;
}

######################################################################
sub get_line($)
######################################################################
{
  my $self = shift || die;

  my $line = $self->{line};

  # Do not use "if ($line)" here as the string consisting of the
  # digit "0" evaluates to false.
  if (defined($line) && length($line) > 0) { return $line; }

  my $file = $self->{file} || die 'No opened file.';
  while($line = <$file>)
  {
    ++$self->{line_nr};
    $line =~ s/^\s+//;
    $line =~ s/[\s\r\n]*$//;
    if ($line !~ m/^(#|$)/)
    {
      return $self->{line} = $line;
    }
  }

  return undef;
}

######################################################################
sub error_sprintf($;$@)
######################################################################
{
  my $self = shift || die;
  my $format = shift;
  my $result = sprintf('Error in %s at line %s: ',
    $self->{filename},
    $self->{line_nr},
  );
  if ($format) { $result .= sprintf($format, @_); }
  return $result;
}

######################################################################
sub scan_token($)
######################################################################
{
  my $self = shift || die;

  for(;;)
  {
    my $line = $self->get_line();
    if (!defined($line))	# end of file
    {
      return $self->{token} = undef;
    }

    if ($line =~ m/
      ^(?:
	"([^"]*)" |		# quoted string
	([\w\/-][.\w\/-]*) |	# identifier, path, option, integer, ip-address
	([{}:])  		# special character
      ) \s* (.*) $
      /x)
    {
      $self->{line} = $4;
      # Do not use "$1 || $2" here, as "0" is a valid token.
      return $self->{token} = defined($1) ? $1 : defined($2) ? $2 : $3;
    }
    elsif ($line =~ m/^#/)		# comment
    {
      delete $self->{line};
    }
    else				# illegal character
    {
      die $self->error_sprintf('Illegal character at %s', $line);
    }
  }
}

######################################################################
sub get_token($)
######################################################################
{
  my $self = shift || die;

  my $token = $self->{token};
  return defined($token) ? $token : $self->scan_token();
}

######################################################################
sub expect_token($$;$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $dscr = shift || die 'No $dscr';
  my $value = shift;

  my $token = $self->get_token();
  if (!defined($token))
  {
    die $self->error_sprintf('Expected %s, not end of file.', $dscr);
  }
  if (defined($value) && $value ne $token)
  {
    die $self->error_sprintf('Expected %s, not %s.', $token);
  }
  $self->scan_token();	# step over value
  return $token;
}

######################################################################
sub add_parameter($$$$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $rh_node = shift || die 'No $rh_node';
  my $ident = shift || die 'No $rh_node';
  my $value = shift;

  $rh_node->{$ident} = $value;
}

######################################################################
sub read_one_parameter($$$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $keywords = shift || die 'No $keywords';
  my $rh_node = shift || die 'No $rh_node';

  # end-of-file condition must be checked by caller
  my $ident = $self->get_token() || die;

  if (!exists( $keywords->{$ident} ))
  {
    die $self->error_sprintf(
      'Valid identifier expected instead of "%s"',
      $ident
    );
  }

  if (exists( $rh_node->{$ident} ))
  {
    die $self->error_sprintf(
      'Duplicate parameter "%s" in same scope.',
      $ident
    );
  }

  $self->scan_token();
  $self->expect_token(':');
  my $value = $self->expect_token('value');

  my $delegate = $self->{delegate} || $self;
  $delegate->add_parameter($rh_node, $ident, $value);
}

######################################################################
sub read_values($$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $keywords = shift || die 'No $keywords';

  my $rh_node = {};
  for(;;)
  {
    my $ident = $self->get_token();
    if (!defined($ident)) { return $rh_node; }	# end of file
    if ($ident eq '}') { return $rh_node; }	# return from descent
    $self->read_one_parameter($keywords, $rh_node);
  }
}

######################################################################
sub read_peer_group_tree($$;$)
######################################################################
{
  my $self = shift || die 'No $self';
  my $keywords = shift || die 'No $keywords';
  my $rh_node = shift || {};

  for(;;)
  {
    my $token = $self->get_token();
    if (!defined($token)) { return $rh_node; }	# end of file
    elsif ($token eq '}') { return $rh_node; }	# return from descent
    elsif ($token eq 'peer')
    {
      $self->scan_token();	# step over 'peer'
      my $peer_name = $self->expect_token('peer name');
      $self->expect_token('{');
      my $rh_child_node = $self->read_values($keywords);
      $self->expect_token('}');
      $rh_node->{'peer'}->{$peer_name} = $rh_child_node;
    }
    elsif ($token eq 'group')
    {
      $self->scan_token();	# step over 'group'
      my $group_name = $self->expect_token('group name');
      $self->expect_token('{');
      my $rh_child_node = $self->read_peer_group_tree($keywords);
      $self->expect_token('}');
      $rh_node->{'group'}->{$group_name} = $rh_child_node;
    }
    else
    {
      $self->read_one_parameter($keywords, $rh_node);
    }
  }
}

######################################################################
1;
######################################################################
