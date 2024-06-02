#!/bin/sh -x
######################################################################
#
# $Id: make-posts-per-month-stats.sh 652 2012-03-05 08:18:17Z root $
#
# Copyright 2012 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
. "${SCHNUERPEL_DIR}/bin/config-cleanfeed.sh"

dst_dir="${1:-ch}"
groups="${2:-ch.*,soc.culture.swiss}"

make_summary()
{
  local base_dir="$1"
  local month_dir="$2"
  local dir="${base_dir}/${month_dir}"
  (
    sed "s#\${month_dir}#${month_dir}#g" ${base_dir}.head
    cd "${dir}"
    cat posts.txt
    echo ""
    cat clients.txt
    echo ""
    cat paths.txt
  ) > "${dir}/summary.txt"
}

check_cleanfeed()
{
  if [ -d "${CLEANFEED_DEBUG_BATCH_DIRECTORY:-}" ]; then
    for src in "${CLEANFEED_DEBUG_BATCH_DIRECTORY}/"all*
    do
      echo "*** ${src} ***"
      "${SCHNUERPEL_DIR}/bin/count-posts-per-month.pl" \
	    "-dir=${dst_dir}" \
	    "-groups=${groups}" \
	    "-method=headerfile" \
	    < "${src}"
    done
  fi
}

check_nntp()
{
  "${SCHNUERPEL_DIR}/bin/count-posts-per-month.pl" \
    "-dir=${dst_dir}" \
    "-groups=${groups}" \
    "-method=article"
}

make_stats()
{
  "${SCHNUERPEL_DIR}/bin/make-posts-per-month-stats.pl" \
    "-dir=${dst_dir}"
}

[ -d "${dst_dir}" ] || mkdir "${dst_dir}"

check_cleanfeed
check_nntp
make_stats

dir_format='%Y/%m'
this_month=$( date "+${dir_format}" )
prev_month=$( date "+${dir_format}" -d "today -1 month" )
make_summary "${dst_dir}" "${this_month}"
make_summary "${dst_dir}" "${prev_month}"
