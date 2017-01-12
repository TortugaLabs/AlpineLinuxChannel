#!/bin/sh
#
# Configuration
#
GIT_BRANCH=
if [ -n "${TRAVIS_BRANCH:-}" ] ; then
  GIT_BRANCH="$TRAVIS_BRANCH"
else
  GIT_BRANCH="$( cd "$WORLD" && git rev-parse --abbrev-ref HEAD)"
fi
[ -z "$GIT_BRANCH" ] && die 11 "Unknown branch"

case "$GIT_BRANCH" in
#  *3.5*)
#    export APORTS_BRANCH=3.5-stable
#    release=3.5
#    ;;
#  *3.4*)
#    export APORTS_BRANCH=3.4-stable
#    release=3.4
#    ;;
#  edge)
#    export APORTS_BRANCH=master
#    release=edge
#    ;;
  *)
    export APORTS_BRANCH=3.4-stable
    release=3.4
    ;;
esac

export REPO_ROOT=$(readlink -f "$WORLD"/..)

export \
  ARM_RELEASE=$release \
  ARM_MIRROR=http://nl.alpinelinux.org/alpine/ \
  ARM_ARCH=x86_64

# Note, we have the ARM_ARCH fixed to x86_64 because we only 
# ever want to do 64 bit builds here.

