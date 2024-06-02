#!/bin/sh
#
# $Id: newgroup-unwanted.sh 257 2010-01-01 14:40:51Z alba $
#
export "LANG=C"
export "LC_ALL=C"
set -o nounset
set -o errexit

echo ctlinnd throttle newgroup
(
  cat /var/log/news/unwanted.log
# zcat /var/log/news/OLD/unwanted.log.*.gz
) |
sed -ne 's/^[2-9]\{2,\} //p' |
grep -vf $SCHNUERPEL_DIR/etc/hierarchies-with-checkgroups |
grep -vf $SCHNUERPEL_DIR/etc/newgroup-unwanted-exclude |
sort -u |
sed 's/^/ctlinnd newgroup /'
echo ctlinnd go newgroup
