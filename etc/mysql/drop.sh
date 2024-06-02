#!/bin/sh
#
# Shell script to print drop statements in reverse order of create.
#

awk '/^ *create +table +/ { printf "drop table %s;\n",$3 }' \
	mysql-create.sql | tac
