#!/bin/sh
#
# $Id: make-host-file.sh 480 2011-02-27 21:45:09Z alba $
#
# Copyright 2011 Alexander Bartolich
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

hosts='/etc/hosts'
signature='### EVERYTHING BELOW WAS ADDED BY make-host-file. DO NOT EDIT. ###'

awk "/^${signature}/ { exit; }"' { print $0; }' < "${hosts}" > "${hosts}.tmp"
echo "${signature}" >> "${hosts}.tmp"
${SCHNUERPEL_DIR}/bin/make-host-file.pl | sort -k2 >> "${hosts}.tmp"
mv -f "${hosts}.tmp" "${hosts}"
