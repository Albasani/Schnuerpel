#!/bin/sh
#
# $Id: onno-send-load.sh 184 2009-01-04 21:58:58Z alba $
#
######################################################################
#
# Send system load to web site that gathers them from all servers.
# Results are published on:
#    http://www.open-news-network.org/serverstatus/index.php
#    http://wiki.open-news-network.org/index.php/Backtraces
#
######################################################################
export "LANG=C"
export "LC_ALL=C"
set -o nounset
set -o errexit

PASS="$1"
NEWSHOST="news1"

load=$( awk '{ printf "%3.2f\n", 100 - $2 / $1 * 100 }' /proc/uptime )
url="http://www.open-news-network.org/serverstatus/sendload.php?pass=${PASS}&load=${load}"
wget --quiet --no-proxy -O /dev/null "${url}"
