#!/bin/sh
######################################################################
#
# $Id: test-admin-cgi.sh 444 2011-02-15 13:34:53Z alba $
#
# Copyright 2011 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################


[ -n "${DB_USER:-}" ] || export DB_USER=$( sed -ne 's/^user=//p' "${HOME}/.my.cnf" )
[ -n "${DB_PASSWD:-}" ] || export DB_PASSWD=$( sed -ne 's/^password=//p' "${HOME}/.my.cnf" )

. "$SCHNUERPEL_DIR/bin/config.sh"

[ -n "${R_PICTURE_URL:-}" ] || export "R_PICTURE_URL=/picture"
[ -n "${SERVER_NAME:-}" ] || export "SERVER_NAME=$( hostname )"
[ -n "${REMOTE_ADDR:-}" ] || export "REMOTE_ADDR=localhost"
[ -n "${DB_DATABASE:-}" ] || export "DB_DATABASE=DBI:mysql:database=${SCHNUERPEL_MYSQL_DB:-news};host=${SCHNUERPEL_MYSQL_HOST:-localhost}"

perl -w "${SCHNUERPEL_DIR}/etc/cgi/admin/admin.cgi"
