#!/usr/bin/gawk -f
#
# $Id: onno-send-login.awk 205 2009-02-10 21:33:49Z alba $
#
# Copyright 2008 - 2009 Alexander Bartolich
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
######################################################################
#
# ONNO uses the description field in LDAP records to store timestamp
# and server name of last login. Modification of LDAP data requires
# access to the master server. However, authentication is performed
# with slave servers to balance load. Thus, update of login time
# stamps is done asynchronously by a daily cron job that scans log
# files.
#
# This script reads "news.notices" and writes LDIF output suitable
# for ldapmodify.
#
######################################################################

BEGIN {
  if (length(NEWSHOST) == 0)
    NEWSHOST = "news1";
  if (length(LDAPBASE) == 0)
    LDAPBASE = "dc=open-news-network,dc=org";

  YEAR = strftime("%Y", systime());

  MONTH["Jan"] = 01;
  MONTH["Feb"] = 02;
  MONTH["Mar"] = 03;
  MONTH["Apr"] = 04;
  MONTH["May"] = 05;
  MONTH["Jun"] = 06;
  MONTH["Jul"] = 07;
  MONTH["Aug"] = 08;
  MONTH["Sep"] = 09;
  MONTH["Oct"] = 10;
  MONTH["Nov"] = 11;
  MONTH["Dec"] = 12;

  print "version: 1";
}

function add(user, ip,
  t)
{ 
  gsub(/:/, " ", $3);
  t = mktime(sprintf("%s %02d %02d %s\n", YEAR, MONTH[$1], $2, $3));
  if (LOGIN_TIME[user] < t)
  {
    LOGIN_TIME[user] = t;
    if (length(ip) > 0)
      LOGIN_IP[user] = ip;
  }
}

# Sample input from AuthLDAP.pm
# Jan  4 19:40:05 schnuerpel nnrpd[5204]: filter: LDAP authenticated alexander.bartolich@gmx.at 127.0.0.1
/: filter: LDAP authenticated / { add($9, $10) }

# Sample input from ldapcheck
# Jan  4 22:12:45 alpha826 nnrpd[28776]: 127.0.0.1 auth_err binding as uid=alexander.bartolich@gmx.at,dc=open-news-network,dc=org at ldap1.open-news-network.org
/ binding as uid=/ { match($10, /=(.*),dc=/, a); add(a[1], $6) }

END {
  for(user in LOGIN_TIME)
  {
    printf "\ndn: uid=%s,%s\n", user, LDAPBASE;
    print  "changetype: modify";
    print  "replace: description";
    printf "description: %s %s\n", NEWSHOST, LOGIN_TIME[user];
    if (user in LOGIN_IP)
    {
      print  "\nchangetype: modify";
      print  "replace: labeledURI";
      printf "labeledURI: %s\n", LOGIN_IP[user];
    }
  }
}

######################################################################
