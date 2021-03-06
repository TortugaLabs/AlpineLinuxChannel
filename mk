#!/bin/sh
#
# Usage:
#
# - mk world (default) : does everything
# - mk update : Checks APORTS and updates any packages
# - mk build : build packages
# - mk cksum : recalculate source checksums
#
# options:
# - -d : debug on
#


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
export WORLD=$(cd "$(dirname "$0")" && pwd)
[ -z "$WORLD" ] && die 45 "ERROR: Unable to find the world"
[ -z "${IN_ROOTER:-}" ] && exec "$WORLD/scripts/rooter.sh" "$0" "$@"

export scripts="$WORLD/scripts" vrelease=""

while [ "$#" -gt 0 ] ; do
  case "$1" in
    -d|--debug)
      export debug=true
      ;;
    --rel=*)
      export vrelease="${1#--rel=}"
      ;;
    --release=*)
      export vrelease="${1#--release=}"
      ;;
    *)
      break
      ;;
  esac
  shift
done

. "$WORLD/config.sh"



if [ -n "${repo:=}" ] ; then
  repo=$(cd "$repo" && pwd) || exit 1
fi

cd "$WORLD" || exit 1

if [ "$#" -eq 0 ] ; then
  set - world
fi

updscore() {
  local \
    wget="wget -O- -nv" \
    url="http://ow1.localnet/cgi-bin/updstat.cgi?" \
    n="&" \
    app="host=AlpineLinuxChannel-v$release" \
    ver="version=$release-$(date +%Y.%m)"

  $wget "$url$app$n$ver"
}

update() {
  debug "! update from APORTS"
  $scripts/seed.sh "manifest.txt"
}

build() {
  debug "! Building sources"
  repo_dir=$REPO_ROOT/v$ARM_RELEASE/$ARM_ARCH
  repo_keys=$REPO_ROOT/keys
  
  mkdir -p "$repo_dir" "$repo_keys"

  $scripts/arm.sh depsort source testing \
    | $scripts/builder.sh  \
      "$repo_dir" "$repo_keys"

  updscore
}

world() {
  update
  build
}

cksum() {
  find source -name APKBUILD -print0 | xargs -0 $scripts/arm.sh cksum -w
}


for op in "$@"
do
  "$op"
done



