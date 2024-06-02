#!/usr/bin/perl -w
BEGIN { push(@INC, $ENV{'SCHNUERPEL_DIR'} . '/lib'); }
use Schnuerpel::CGI::Globals( module_loop );
module_loop('AdminTable');
