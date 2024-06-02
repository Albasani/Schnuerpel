#!/bin/sh
######################################################################
#
# $Id: config.sh 648 2012-01-04 13:38:10Z alba $
#
# Copyright 2008-2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################

export "LANG=C"
export "LC_ALL=C"
set -o nounset
set -o errexit

# innshellvars modifies $ENV{'HOME'}, so save it
SCHNUERPEL_ORIGINAL_HOME="${HOME}"

for file in \
  '/usr/lib/news/innshellvars' \
  '/usr/lib/news/lib/innshellvars'
do
  [ -r "${file}" ] || continue
  . "${file}"
  [ -r "$LOG" ] && break
  echo "ERROR: ${file} does not define a valid \$LOG"
  exit 1
done

export "HOME=${SCHNUERPEL_ORIGINAL_HOME}"
export "SCHNUERPEL_MYSQL_DB=${SCHNUERPEL_MYSQL_DB:-news}"
