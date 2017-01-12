#!/bin/sh
#++
# = SEEDER(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# seeder - Initialize APORTs sub-trees
#
# == SYNOPSIS
#
# *seeder* _manifest.txt_
#
# == DESCRIPTION
#
# Check APORTS and download missing sources and remove
# sources that are obsolete
#
#--

#
set -euf -o pipefail
# ${debug:=:} "**** Checking APORTS ****"


fatal() {
  echo "$@" 1>&2
  exit 1
}

srcdir="testing"

[ $# -ne 1 ] && fatal "Usage: $0 <manifest>"

manifest="$1"

[ ! -f "$manifest" ] && fatal "Missing manifest; $manifest"
[ ! -d "$srcdir" ] && mkdir -p "$srcdir"

srcs="$(find "$srcdir" -mindepth 1 -maxdepth 1 -type d)"

for d in $srcs
do
 # $debug "Marking $d/.t"
 > "$d/.t"
done

exec <"$manifest" || exit 1
while read ln
do
  ln=$(echo "$ln" | sed 's/#.*$//')
  ln=$(echo $ln)
  [ -z "$ln" ] && continue

  # $debug ": $ln"
  if [ -f "$ln/.t" ] ; then
    rm -f "$ln/.t"
  fi

  "$scripts/aports.sh" "$ln"
done

for d in $srcs
do
  [ -f "$d/.t" ] || continue
  echo "Removing $d"
  rm -rf $d
done

