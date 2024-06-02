package Schnuerpel::CGI::TableCtrl;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw( new );

use strict;
use encoding 'utf8';
use CGI( -utf8 );
use CGI::Carp qw( fatalsToBrowser );

use Schnuerpel::CGI::UserMgr qw(
  &GET_PARAM_INT
);

######################################################################

use constant PAGE_SIZE => 200;

######################################################################
sub new($$;$$)
######################################################################
{
  my $proto = shift;
  my $table_name = shift || die;

  # for add_hidden and add_params_to_url an instance without
  # fields can be constructed, so no die
  my $r_fields = shift;

  my $from_where = shift;

  my $class = ref($proto) || $proto;
  my ( %self ) = @_;
  my $self = \%self;

  bless($self, $class);

  $self->{table_name} = $table_name;
  $self->{fields} = $r_fields;
  $self->{error} = [];
  $self->{sort_param} = 'sort_' . $table_name;
  $self->{start_param} = 'start_' . $table_name;
  $self->{from_where} = $from_where;

  return $self;
}

######################################################################
sub add_hidden($$)
######################################################################
{
  my $self = shift || die;
  my $r_hidden = shift || die;

  push @$r_hidden, $self->{start_param}, $self->{sort_param};
}

######################################################################
sub add_params_to_url($$)
######################################################################
{
  my $self = shift || die;
  my $userMgr = shift || die;

  return
    'table=' . $self->{table_name} . '&' .
    $self->{start_param} . '=' .
    $self->get_start_param($userMgr) . '&' .
    $self->{sort_param} . '=' .
    $self->get_sort_param($userMgr) . '&'
    ;
}

######################################################################
sub append_sql_where($$$)
######################################################################
{
  my $r_sql = shift || die;
  my $key = shift;
  my $items = shift;

  if ($$r_sql =~ m/\bWHERE\b/i)
    { $$r_sql .= "\nAND "; }
  else
    { $$r_sql .= "\nWHERE "; }

  my $cond = $key . " = ?\n";
  $$r_sql .= $cond;
  my $or = 'OR ' . $cond;
  for(my $i = $#$items; $i > 0; $i--)
    { $$r_sql .= $or; }
}

######################################################################
sub get_sort_param($$)
######################################################################
{
  my $self = shift || die;
  my $userMgr = shift || die;

  my $sort_param = $self->{sort_param} || die;
  my $sort = $userMgr->get_param($sort_param, GET_PARAM_INT);
  $sort = '+1' unless(defined($sort));
  return $self->{sort} = $sort;
}

######################################################################
sub get_start_param($$)
######################################################################
{
  my $self = shift || die;
  my $userMgr = shift || die;

  my $start_param = $self->{start_param} || die;
  my $start = $userMgr->get_param($start_param, GET_PARAM_INT);
  $start = 0 unless(defined($start));
  return $self->{start} = $start;
}

######################################################################
sub select_rows($$;$)
######################################################################
{
  my $self = shift || die;
  my $userMgr = shift || die;
  my $r_selected = shift;

  my $table_name = $self->{table_name} || die;
  my $r_fields = $self->{fields} || die;
  my @fields = map { my $a = $_; $a =~ s#^[<>-]##; $a; } @$r_fields;

  my $r_bind = [];
  my $where = "FROM " . $table_name . "\n";
  if (exists( $self->{from_where}  ))
  {
    $where .= $self->{from_where};
  }
  if (defined($r_selected) && $#$r_selected >= 0)
  {
    append_sql_where(\$where, $r_fields->[0], $r_selected);
    $r_bind = $r_selected;
    # printf "<pre>%d</pre>\n", $#$r_selected;
    # printf "<pre>%s</pre>\n", $where;
  }

  my $dbc = $userMgr->{DBC} || die;
  {
    my $row = $dbc->selectrow_arrayref("SELECT COUNT(*)\n" . $where);
    if (defined($row) && $#$row == 0)
    {
      $self->{total_nr_rows} = $row->[0];
    }
  }

  my $sql = "SELECT " . join(', ', @fields) . "\n" . $where;

  my $sort = $self->get_sort_param($userMgr);
  my $sort_field = $fields[abs($sort)];
  $sort_field =~ s/.*\s//; # handle column alias
  if (defined($sort_field))
  {
    $sql .=
      "\nORDER BY " . $sort_field .
      ($sort > 0 ? " ASC\n" : " DESC\n");
  }

  my $start = $self->get_start_param($userMgr);
  $sql .= 'LIMIT ' . $start . ',' . PAGE_SIZE . "\n";

  my $rows = $self->{rows} = $userMgr->db_select_all($sql, $r_bind);
  return 1 if (defined($rows));

  if ($dbc->err)
  {
    print CGI::pre( $dbc->errstr() );
    print CGI::pre( $sql );
  }
  $dbc->rollback() || die "rollback\n" . $dbc->errstr();
  return 0;
}

######################################################################
sub getURIwithParam($;$)
######################################################################
{
  my $self = shift || die;
  my $param_name = shift;

  # my $uri = $ENV{REQUEST_URI};
  my $uri = $ENV{SCRIPT_NAME} . '?' . $ENV{QUERY_STRING};

  $uri =~ s#&amp;#\&#g;
  $uri =~ s#([?&/])$param_name=[+-]?\d+&*#$1#g;
  $uri =~ s#[?&]+$##;
  $uri =~ s#&#&amp;#g;

  $uri .= ($uri =~ m#[^/]*\?[^/]*$#) ? '&amp;' : '?';
  return $uri . $param_name . '=';
}

######################################################################
sub buildPageTabs($)
######################################################################
{
  my $self = shift || die;

  return $self->{page_tabs} if(exists($self->{page_tabs}));

  my $uri = $self->getURIwithParam( $self->{start_param} );
  my $total_nr_rows = $self->{total_nr_rows};
  my $i = 0;
  my $result = '';
  for(my $pos = 0; $pos < $total_nr_rows; $pos += PAGE_SIZE)
  {
    $result .= sprintf("<a href=\"%s%d\">%d</a>\n", $uri, $pos, ++$i);
  }
  return $self->{page_tabs} = $result;
}

######################################################################
sub printPageTabs($$$$)
######################################################################
{
  my $self = shift || die;
  my $left_text = shift;
  my $column_entity = shift;

  $column_entity = 'td' unless(defined($column_entity));
  my $r_fields = $self->{fields} || die;

  print
    "<", $column_entity, " colspan=\"", $#$r_fields, "\">",
    "<span style=\"float:left\">", $left_text, "</span>\n",
    "<span style=\"float:right\">",
      $self->buildPageTabs(),
    "</span>\n",
    "</", $column_entity, ">\n";
}

######################################################################
sub printHeader($;$)
######################################################################
{
  my $self = shift || die;
  my $buttons = shift;
  $buttons = '' unless(defined($buttons));

  my $r_fields = $self->{fields} || die;

  #
  # http://albasani.net/user/admin/?table=r_user
  #
  my $uri = $self->getURIwithParam( $self->{sort_param} );

  my $sort = $self->{sort};
  my $abs_sort = abs($sort);
  my $tabs_string = $self->buildPageTabs();

  print
    "<table class=\"odd_even\">\n",
    "<tr><th rowspan=\"2\">",
      "<img src=\"/picture/arrow-to-top-right.gif\"/>",
    "</th>";
  $self->printPageTabs($buttons, 'th');
  print
    "</tr>\n",
    "<tr>"
    ;

  for(my $i = 1; $i <= $#$r_fields; $i++)
  {
    my $a = $r_fields->[$i];
    my $b = ($a =~ m#\s+AS\s+(.*)# ? $1 : $a);
    $b =~ s#^[<>-]##;
    printf "<th><a href=\"%s%+d\">%s</a></th>\n",
      $uri,
      ($i == $abs_sort) ? -$sort : $i,
      $b;
  }
  print
    "\n</tr>\n";
}

######################################################################
sub printFooter($)
######################################################################
{
  my $self = shift || die;
  my $r_fields = $self->{fields} || die;

  my $nr;
  if (exists( $self->{total_nr_rows} ))
  {
    $nr = $self->{total_nr_rows};
  }
  else
  {
    my $data = $self->{rows} || die;
    $nr = 1 + $#$data;
  }

  print
    "<tr class=\"last_row\">\n",
    "<td align=\"center\">",
      "<img src=\"/picture/marker-up-black.gif\"/>",
    "</td>\n";
  $self->printPageTabs( $nr == 1 ? "1 row" : "$nr rows" );
  print
    "</tr>\n",
    "</table>\n";
}    

######################################################################
sub printTable($;$$)
######################################################################
{
  my $self = shift() || die;
  my $radio = shift;
  my $buttons = shift;
  my $r_selected = shift;

  # note that "shift || die" strikes integer value 0 

  my $table_name = $self->{table_name} || die;
  my $r_fields = $self->{fields} || die;
  my $data = $self->{rows} || die;

  if ($#$data < 0)
  {
    print "<p>No records available.</p>\n";
    return 0;
  }

  my $input_type = $radio ? 'radio' : 'checkbox';

  my %selected;
  if (defined($r_selected))
  {
    for my $selected(@$r_selected)
      { $selected{$selected} = 1; }
  }

  $self->printHeader($buttons);

  my $row_nr = 0;
  for my $row(@$data)
  {
    next if ($#$row < 0);
    
    my $first = $row->[0];
    die unless(defined($first));

    my $checked = exists( $selected{$first} )
    ? ' checked="checked"'
    : '';

    printf "<tr class=\"%s\">\n", (++$row_nr & 1) ? 'oe_odd' : 'oe_even';
    print
      "<td><input type=\"", $input_type, "\" name=\"",
      $table_name,
      "\" value=\"",
      $first,
      '"',
      $checked,
      "/></td>\n";
    
    for(my $i = 1; $i <= $#$row; $i++)
    {
      my $align = substr($r_fields->[$i], 0, 1);
      if ($align eq '>')
        { print "<td align=\"right\">"; }
      elsif ($align eq '-')
        { print "<td align=\"center\">"; }
      else
        { print "<td>"; }
      print $row->[$i];
      print "</td>\n";
    }

    print "</tr>\n";
  }

  $self->printFooter();
}

1;
