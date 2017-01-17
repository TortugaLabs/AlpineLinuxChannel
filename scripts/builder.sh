#!/bin/sh
#++
# = BUILDER(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# builder - Builds a sorted list of APKs
#
# == SYNOPSIS
#
# *builder* repodir repo_keys
#
# == DESCRIPTION
#
# Read from standard input a list of packages to build.
#
#  
#--


#### start common stuff ####
version=$( grep '^# :Revision:' "$0" | cut -d: -f3 | tr -d ' ')
set -euf -o pipefail
die() {
  ## Show a message and exit
  ## # USAGE
  ##   die exit_code [msg]
  ## # ARGS
  ## * exit_code -- Exit code
  ## * msg -- Text to show on stderr
  local exit_code="$1"
  shift
  echo "$@" 2>&1
  exit $exit_code
}
debug() {
  ## Will show a message if debug is non-empty
  [ -z "${debug:=y}" ] && return
  echo "$@"
}
manual() {
  ## Show embedded (manify) documentation
  sed -n -e '/^#++$/,$p' "$0" -e '/^#--$/q' "$1" | grep '^#' | sed -e 's/^# //' -e 's/^#//'
  exit 0
}
usage() {
  ## Show usage
  echo 'Usage:'
  sed -n -e '/^#++$/,$p' "$0" -e '/^#--$/q' "$1" | grep '^#' | \
    sed -n -e '/^# == SYNOPSIS/,$p'  | ( read x ; cat ) | \
    sed -e '/^# == /q' | sed 's/^# == .*//' | sed -e 's/^# *//' | \
    (while read l ; do [ -n "$l" ] && echo '    '"$l" ; done) && :
  [ -n "$version" ] && echo "$(basename "$0") v$version"
  exit
}
#### stop common stuff ####

##################################################################
# Functions
##################################################################

update_buildstats() {
  local \
    statsfile="$1" \
    pkg="$2" \
    pvr="$3"
  shift 3

  local inp="$(awk -F: '$1 != "'"$pkg"'" { print }' "$statsfile" | grep ':')"
  (
    [ -n "$inp" ] && echo "$inp"
    echo "$pkg:$pvr:$*"
  ) >"$statsfile"
}
getapks_buildstats() {
  local \
    statsfile="$1" \
    pkg="$2" \
    pvr="$3"
  awk -F: '$1 == "'"$pkg"'" && $2 == "'"$pvr"'" { print $3 }' "$statsfile"
}


##################################################################
# MAIN
##################################################################
main() {
  local \
    chroot_ready=false \
    statsfile="$repo_dir"/.buildstats \
    chroot_pkgs="" \
    local build_dir="$repo_dir/._build"

  [ ! -d "$repo_dir" ] && die 72 "REPO DIR NON EXISTENT"
  [ ! -d "$repo_keys" ] && die 73 "REPO KEYS NON EXISTENT"

  if [ -f "$repo_dir"/APKINDEX.tar.gz ] ; then
    local need_index=false
  else
    local need_index=true
  fi
  [ ! -f "$statsfile" ] && >"$statsfile"

  local pkg pvr i
  while read pkg
  do
    [ ! -f "$pkg/APKBUILD" ] && continue

    pvr=$(set +euf ;. $pkg/APKBUILD ; echo $pkgver-r$pkgrel)
    if [ -z "$pvr" ] ; then
      echo "$pkg: Missing pkgver/pkgrel" 1>&2
      continue
    fi
    
    local apks="$(getapks_buildstats "$statsfile" "$pkg" "$pvr")"
    if [ -n "$apks" ] ;then
      # Already built...
      debug "$pkg $pvr - $apks"
      if $chroot_ready ; then
	for i in $apks
	do
	  [ -f "$repo_dir/$i" ] && $arm i "$repo_dir/$i"
	done
      else
	if [ -z "$chroot_pkgs" ] ; then
	  chroot_pkgs="$apks"
	else
	  chroot_pkgs="$chroot_pkgs $apks"
	fi
      fi
      continue
    fi

    if ! $chroot_ready ; then
      $arm create || :
      if [ -n "$chroot_pkgs" ] ; then
	for i in $chroot_pkgs
	do
	  $arm i "$repo_dir/$i"
	done
      fi
      chroot_ready=true
    fi

    [ -d "$build_dir" ] && rm -rf "$build_dir"
    mkdir -p "$build_dir"
    $arm b --output="$build_dir" "$pkg"
    local output="$(find "$build_dir" -name '*.apk' -maxdepth 1 -mindepth 1 -type f -printf '%f\n')"
    if [ -n "$output" ] ; then
      for i in $output
      do
        [ -f "$repo_dir/$i" ] && rm -f "$repo_dir/$i"
        cp -l$(debug v) "$build_dir/$i" "$repo_dir"
      done
      update_buildstats "$statsfile" "$pkg" "$pvr" $output
      need_index=true
    fi
  done

  if $need_index ; then
    if ! $chroot_ready ; then
      $arm create || :
      chroot_ready=true
    fi
    $arm apkindex --keystore="$repo_keys" "$repo_dir"
  fi

  $chroot_ready && $arm nuke
    
  rm -rf "$build_dir"
}

##################################################################
# Command-line
##################################################################
arm="$(cd "$(dirname $0)" && pwd)/arm.sh"
type $arm >/dev/null || die 68 "$arm missing"

[ $# -ne 2 ] && usage "$0"

repo_dir="$(readlink -f "$1")"
repo_keys="$(readlink -f "$2")"
shift 2

main "$@"

