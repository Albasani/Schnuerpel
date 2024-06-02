#!/bin/sh
######################################################################
#
# $Id: update-host-list.sh 274 2010-02-09 22:26:56Z alba $
#
# Copyright 2009-2010 Alexander Bartolich
#
######################################################################
#
# To actually download files first parameter must be "wget" 
#
######################################################################
export "LANG=C"
export "LC_CTYPE=C"
set -o nounset
set -o errexit

######################################################################
wget_one()
######################################################################
{
  local name="$1"
  local url="$2"

  if wget -O "${name}.tmp" "${url}"
  then mv -u "${name}.tmp" "${name}.csv"
  else echo $?
  fi
}

######################################################################
wget_all()
######################################################################
{
  # http://www.torproject.org/faq-abuse.html.de#Bans
  wget_one 'torproject.org' \
    'https://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=78.46.73.112'

  wget_one 'kgprog.com' \
    'http://torstatus.kgprog.com/ip_list_exit.php/Tor_ip_list_EXIT.csv'
}

######################################################################
process_one()
######################################################################
{
  local type="$1"
  local dst="HostList/$1.pm"

  [ -d HostList ] || mkdir HostList < /dev/null
  "${SCHNUERPEL_DIR}/bin/update-host-list.pl" "-TYPE=${type}" > "$dst"
  perl -wc "$dst" < /dev/null || mv -f "$dst" "$dst-broken"
}

######################################################################
# main
######################################################################
cd "${SCHNUERPEL_VAR}"
pwd

# remove stale files
find . -maxdepth 1 -type f -name '*.csv' -mtime +7 -exec rm {} \+

[ "${1:-}" = "wget" ] && wget_all

cat *.csv | process_one tor
ip addr | sed -ne 's/^ *inet \([0-9.]*\).*/\1/p' | process_one local

######################################################################
