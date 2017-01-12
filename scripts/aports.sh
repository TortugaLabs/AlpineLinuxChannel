#!/bin/sh
#++
# = APORTS(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# aports - Download APORTS scripts
#
# == SYNOPSIS
#
# *aports* _[--host=url]_ _[--cgit=<cgit>]_ _[--branch=<branch>]_ <repo>/<project>
#
# == DESCRIPTION
#
# This checks in the AlpineLinux `cgit` web site and downloads the
# relevant files.
#
# == OPTIONS
#
# *--host=* _url_::
#    Alpine Linux _cgit_ URL host.
# *--cgit=* _path_::
#    Path to the _cgit_ page.
# *--branch=* _branch_::
#    Branch to retrieve.
#
# == ENVIRONMENT
#
# - APORTS_BRANCH:: Branch to use
# - APORTS_HOST:: URL host
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

cgit="cgit/aports/tree"
branch=${APORTS_BRANCH:-master}
host=${APORTS_HOST:-http://git.alpinelinux.org}
wget="wget -q"

while [ $# -gt 0 ]
do
  case "$1" in
    --host=*)
      host=${1#--host=}
      ;;
    --cgit=*)
      cgit=${1#--cgit=}
      ;;
    --branch=*)
      branch=${1#--branch=}
      ;;
    --help|-h)
      manual "$0"
      ;;
    *)
      break
      ;;
  esac
  shift
done

mkurl() {
  local \
    url="$1" \
    branch="$2"
  echo -n "$1"
  [ -n "$branch" ] && echo '?h='"$branch"
}
    

get_git_objects() {
  local \
    url="$1" \
    dir="$2" \
    branch="$3"
  $wget -O- "$(mkurl "$url/$dir" $branch)" \
  | sed -e 's/href=/\nhref=/g' | grep 'plain' | sed -e 's/>/\n/' \
  | grep 'href=' | sed -e 's/href=["'\'']//' | sed -e 's/["'\'']$//' \
  | cut -d'?' -f1
}

dl_aports() {
  local prj="$1"

  if [ -d "$prj" ] ; then
    if [ -f "$prj/.branch" ] ; then
      cbranch=$(cat "$prj/.branch")
      if [ -n "$cbranch" ] ; then
        [ "$cbranch" != "$branch" ] && rm -rf "$prj"
      fi
    fi
  fi

  mkdir -p "$prj"

  local objects="$(get_git_objects $host/$cgit $prj $branch)"
  if [ -z "$objects" ] ; then
    echo "$prj: No objects found" 2>&1
    return 1
  fi
  
  echo "$objects" | (
    local rv=0
    while read wpath
    do
      local fpath="$(basename "$wpath")"
      
      if $wget -O "$prj/$fpath.$$" "$(mkurl "$host$wpath" $branch)" ; then
        # DL succesful
	if [ -f "$prj/$fpath" ] ; then
	  if cmp "$prj/$fpath" "$prj/$fpath.$$" ; then
	    rm -f "$prj/$fpath.$$"
	  else
	    rm "$prj/$fpath"
	    mv "$prj/$fpath.$$" "$prj/$fpath"
	    echo "Updating $prj/$fpath" 2>&1
	  fi
	else
	  mv "$prj/$fpath.$$" "$prj/$fpath"
	  echo "Creating $prj/$fpath" 2>&1
	fi
      else
	rm -f "$prj/$fpath.$$"
	rv=$(expr $rv + 1)
      fi
    done
    if [ $rv -eq 0 ] ; then
      echo $branch > "$prj/.branch"
    else
      exit 1
    fi
  )
}

[ $# -eq 0 ] && usage "$0"

rv=0
for prj in "$@"
do
  dl_aports "$prj" || rv=$(expr $rv + 1)
done

exit $rv

    
