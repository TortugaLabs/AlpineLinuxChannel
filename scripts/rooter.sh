#!/bin/sh
#++
# = ROOTER(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# rooter - Make SUDO more persistent
#
# == SYNOPSIS
#
# *rooter* cmd
#
# == DESCRIPTION
#
# Retrieves root permission (authenticates sudo)
# at the start of the script and then keeps
# calling sudo to keep it warm
#
# == ENVIRONMENT
#
# - IN_ROOTER:: Set to the PID of the rooter process to indicate
#   that a program is running with `rooter`.
#--

cleanup() {
  if [ -n "$rootkeepr" ] ; then
    kill "$rootkeepr" || kill -9 "$rootkeepr"
  fi
}
trap cleanup EXIT


if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root=sudo
  echo 'Obtaining root permissions'
  $root true || exit 1
  (
    while true
    do
      sleep 60
      $root true
    done
  ) &
  rootkeepr=$!
fi

export IN_ROOTER=$$

"$@"

