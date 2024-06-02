#!/bin/sh
######################################################################
#
# $Id: config-cleanfeed.sh 649 2012-01-04 13:38:26Z alba $
#
# Copyright 2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
. "${SCHNUERPEL_DIR}/bin/config.sh"

if [ -r "${PERL_FILTER_INND:-}" ]; then
  CLEANFEED_DEBUG_BATCH_DIRECTORY=$(
    perl -e "require '${PERL_FILTER_INND}';" \
	-e 'print $config{debug_batch_directory};'
  )
fi
