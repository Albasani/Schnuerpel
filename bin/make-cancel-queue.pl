#!/usr/bin/perl -ws
#
# $Id: make-cancel-queue.pl 631 2011-12-25 21:16:04Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# Uses Schnuerpel::HeaderList to read a list of article headers.
# Writes cancel control messages. Use send-queue.pl to post them
# via NNTP.
#
######################################################################
use strict;
use Schnuerpel::HeaderList qw( enum_headers_file );
use Schnuerpel::OnArticle::MakeCancel();

######################################################################
# MAIN
######################################################################

$::HEADERS = 'headers' if (!$::HEADERS);

my $oa_mc = Schnuerpel::OnArticle::MakeCancel->new();
enum_headers_file( filename => $::HEADERS, delegate => $oa_mc ); 
