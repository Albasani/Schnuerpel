#!/bin/sh
#
# $Id: rmgroup-empty.sh 190 2009-01-07 14:31:28Z alba $
#
. "${SCHNUERPEL_DIR}/bin/config.sh"

num=${1:-500}
echo ctlinnd throttle rmgroup

egrep -if "${SCHNUERPEL_DIR}/etc/rmgroup-empty-include" "${ACTIVE}" |
awk '$2 - $3 < 0 { printf "ctlinnd rmgroup %s # %d\n", $1, $2 - $3; }' |
head "-${num}"

echo ctlinnd go rmgroup
