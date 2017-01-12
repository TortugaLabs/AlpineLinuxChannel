#!/bin/sh
#++
# = ARM(8)
# :Revision: 1.0
# :Author: A Liu Ly
#
# == NAME
#
# arm - APK Root Manager
#
# == SYNOPSIS
#
# *arm* _global-options_ *op* _args_
#
# == DESCRIPTION
#
# Used to manage Alpine Linux chroots
#
# == GLOBAL OPTIONS
#
# *--release=* _x.y_::
#    Alpine Linux release
# *--arch=* _x86_64|x86_::
#    Architecture to use
# *--mirror=* _http_::
#    URL of AlpineLinux mirror
# *--scratch-dir=* _path_::
#    Location of chroots.
#
# == COMMANDS
#
# Standard user commands:
#
# *create|c|mkchroot* _[--chroot=x]_::
#    Create a new|clean chroot (template).
# *build|b* [--cuser=user] [--cuid=uid] [--no-init] [--chroot=chroot] [--wdir=wdir] --output=dir [src]::
#    Run abuild on the specified directory.
#    If a $WORLD/patches/{pkgname}[-rel|-arch].patch is found, then
#    it will be applied.
# *apkindex* [--keystore=x] repo::
#    Create an index for the given repo.  If the --keystore option
#    is specified, the public key will be saved in that location.
#
# Utility commands:
#
# *enter|e* chroot [opts] [cmd]::
#    Enter the chroot executing the command (or /bin/sh).
#    The following options are recognized:
#    - --bind=src:target::
#      Binds the source directory in the chroot as target.
#    - --init::
#      Initializes the chroot if not present
#    - --chroot=path
#    - --user|-u::
#      Will run as user.
#    - --root|-r::
#      Will run as root.
#    - --template|-t::
#      Enter the clean chroot template
# *help|h*::
#    Show help manual.
# *upgrade|u* [--chroot=x] [--user]::
#    Bring chroot to the latest level.  Normally operates on templates
#    unless _--user_ is specified.
# *keygen* --name=name --email=email [--chroot=x]::
#    Create a basic $HOME/.abuild directory.
# *depsort* [directories ...]::
#    Sort dependancies.  If no directories specified, it will read
#    from STDIN lines with paths to source folders and/or APKBUILD's.
#    If directories are provided, it will find in the APKBUILD files.
#    It will then process the found sources and output an ordered
#    list of APKs suitable for building.
# *nuke|n* _[--chroot=x]_::
#    Remove the specified chroots
# *list|l* _[--chroot=x]_ _[--user]_ _[ls-opts]_::
#    List the packages available in a chroot's local repo.
# *inject|i* _[--chroot=x]_ _[--user]_ apks::
#    Inject the specified pkgs into a chroot's local repo.
# *delete|d*  _[--chroot=x]_ _[--user]_::
#    Delete all the pkgs in a chroot's local repo.
#
# == FILES
#
# $HOME/.arm_prefs::
#    Defaults for the arm script
# $HOME/.abuild/::
#    Defaults for the abuild environment.
#
# == ENVIRONMENT
#
# - ARM_MIRROR:: Mirror URL
# - ARM_CHROOTS:: chroots directory
# - ARM_RELEASE:: Preferred Alpine Linux release
# - ARM_ARCH:: Architecture
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
basearch() {
  if [ x"$(uname -m)" = x"x86_64" ] ; then
    echo "x86_64"
  else
    echo "x86"
  fi
}

release() {
  ## Given a release name, create a vtag
  case "$1" in
    *.*)
      echo "v$1"
      ;;
    edge|latest-stable)
      echo "$1"
      ;;
    *)
      echo "latest-stable"
  esac
}

get_apk_list() {
  ## Get a list of APK files in a repository...
  ## # USAGE
  ##   get_apk_list mirror release arch
  ## # ARGS
  ## * mirror -- Alpine Linux mirror URL
  ## * release -- release to use
  ## * arch -- architecture (x86_64|x86)
  ## # OUTPUT
  ## List of found APKs
  local \
    mirror="$1" \
    release="$2" \
    x_arch="$3"

  $wget -O- $mirror/$(release $release)/main/$x_arch/ \
    | sed -e 's/href=/\nhref=/' | sed -e 's/>/\n/' \
    | grep 'href=' |grep 'apk' \
    | sed -e 's/href=["'\'']//' | sed -e 's/apk["'\'']/apk/'
}

get_apk_tool() {
  ## Get static APK tool
  ## # USAGE
  ##   get_apk_tool mirror release arch apk exe
  ## # ARGS
  ## * mirror -- Alpine Linux mirror URL
  ## * release -- release to use
  ## * arch -- architecture (x86_64|x86)
  ## * apk -- APK name
  ## * exe -- destination exe file
  ## # RETURNS
  ## 0 on success, 1 on error
  local \
    mirror="$1" \
    release="$2" \
    x_arch="$3" \
    apk="$4" \
    exe="$5"
  [ -x "$exe" ] && return 0
    
  local temp=$(mktemp -d) rv=1

  if $wget -O$temp/apk-tools-static.apk $mirror/$(release $release)/main/$x_arch/$apk_tools_apk ; then
    if tar -C "$temp" -zxf $temp/apk-tools-static.apk ; then
      if [ -x $temp/sbin/apk.static ] ; then
        debug saving $exe
        cp -a$(debug v) $temp/sbin/apk.static "$exe" && rv=0
      fi
    fi
  fi
  rm -rf "$temp"
  return $rv
}

query_apk() {
  ## Query APKBUILD file
  ## # USAGE
  ##   query_apk APKBUILD [var ...]
  ## # ARGS
  ## * APKBUILD -- Path to APKBUILD file
  ## * var -- one or more variables to query
  ## # OUTPUT
  ## Will print the value of `var`.  If multiple `var`s are specified
  ## then they will printed so that the output can be eval'ed.
  ## If no `var` is specified, `pkgname` will be printed.
  ## # RETURNS
  ## 1 if APKBUILD is not found.
  local apk="$1"
  [ ! -f "$apk" ] && return 1
  shift

  (
    [ $# -eq 0 ] && set - pkgname
    
    [ -n "${x_arch:-}" ] && local CARCH="${x_arch}"
    local subpackages= srcdir= var
 
    . "$apk"
    if [ $# -eq 1 ] ; then
      eval 'var="$'"$1"'"'
      echo $var
    else
      (
	for var in "$@"
	do
	  declare -p "$var"
	done
      ) | sed -e 's/^declare -. //'
    fi
  )
}

create_chroot() {
  ## Create a new chroot from scratch
  ## # USAGE
  ##   create_chroot mirror release arch
  ## # ARGS
  ## * mirror -- Alpine Linux mirror URL
  ## * release -- release to use
  ## * arch -- architecture (x86_64|x86)
  ## * chroot -- target chroot
  ## 
  local \
    mirror="$1" \
    release="$2" \
    x_arch="$3" \
    chroot="$4"

  [ -d "$chroot" ] && die 138 "$chroot: already exists"

  local apk_list="$(get_apk_list "$mirror" "$release" "$x_arch")"
  [ -z "$apk_list" ] && die 103 "No APK files found"
  debug Pkgs Found: $(echo "$apk_list" | wc -l)
  local apk_tools_apk="$(echo "$apk_list" | grep 'apk-tools-static-')"
  [ -z "$apk_tools_apk" ] && die 104 APK tools pkg not found
  local apktool="$chroot.apktool"
      chroot="$(readlink -f "$chroot")"
  local apktool="$(mktemp)"
  trap "rm -f $apktool" EXIT
  debug selected $apk_tools_apk "($apktool)"
  get_apk_tool "$mirror" "$release" "$x_arch" "$apk_tools_apk" "$apktool"

  $root mkdir -p "$chroot"
  $root tee "$chroot/.arm_cfg" <<-EOF
	created=$(date +%s) # $(date +%Y-%m-%d_%H:%M:%S)
	creator=$(id -u -n)
	creator_id=$(id -u)
	mirror=$mirror
	release=$release
	x_arch=$x_arch
	EOF
  $root mkdir -p "$chroot/dev"
  # Set-up devices...
  local dev
  for dev in \
    666:/dev/null:c:1:3 \
    666:/dev/full:c:1:7 666:/dev/ptmx:c:5:2 644:/dev/random:c:1:8 \
    644:/dev/urandom:c:1:9 666:/dev/zero:c:1:5 666:/dev/tty:c:5:0
  do
    local \
      mode=$(echo "$dev" | cut -d: -f1) \
      node=$(echo "$dev" | cut -d: -f2- | tr : ' ')
    $root mknod -m $mode ${chroot}${node}
  done

  $root "$apktool" \
    -X $mirror/$(release $release)/main \
    -U --allow-untrusted \
    --arch $x_arch \
    --root "$chroot" \
    --initdb \
    add alpine-base alpine-sdk

  $root mkdir -p $chroot/etc/apk
  $root tee $chroot/etc/apk/repositories <<-EOF
	$mirror/$(release $release)/main
	$mirror/$(release $release)/community
	/local
	EOF
  $root mkdir -p $chroot/home
  $root tee -a $chroot/etc/sudoers <<-EOF
	%abuild ALL=(ALL) NOPASSWD: ALL
	Defaults env_keep += "http_proxy ftp_proxy https_proxy"
	EOF

  $root mkdir -p $chroot/local/$x_arch
}

enter_chroot() {
  ## Enter a chroot environment
  ## # USAGE
  ##   enter_chroot [--bind=src:dst] chroot_dir cmd
  ## # ARGS
  ## * --bind=src:dst -- The directory will be mount-bind in chroot
  ## * chroot_dir -- chroot directory
  ## * cmd -- command to execute

  local binds="/proc:proc /sys:sys /dev:dev"
  while [ "$#" -gt 0 ] ; do
    case "$1" in
    --bind=*)
      binds="$binds ${1#--bind=}"
      ;;
    -b)
      binds="$binds $2"
      shift
      ;;
    -b*)
      binds="$binds ${1#-b}"
      ;;
    *)
      break;
      ;;
    esac
    shift
  done

  local chroot="$(readlink -f "$1")"
  [ ! -d "$chroot" ] && die 107 "$1: Not found"
  shift
  [ ! -f "$chroot/.arm_cfg" ] && die 126 "$chroot: Invalid chroot"
  exec 9<"$chroot/.arm_cfg"
  if ! flock -x -n 9 ; then
    echo "Waiting for lock..."
    flock -x 9 || return 1
  fi 
  
  local error=no
  local trapcmd="$cleanup Unmounting binds..." b c
  for b in $binds
  do
    local \
      origin="$(echo $b | cut -d: -f1)" \
      target="$(echo $b | cut -d: -f2)"

    if [ ! -d "$origin" ] ; then
      echo "Bind error: $origin"
      error=yes
      continue
    fi
    [ ! -d "$chroot/$target" ] && $root mkdir -p "$chroot/$target"
    if $root mount -o bind $origin $chroot/$target ; then
      trapcmd="$trapcmd ; $root umount $chroot/$target"
    else
      error=yes
    fi
  done
  if [ $error = yes ] ; then
    eval $trapcmd
    exec 9<&-
    return 102
  fi
  
  [ "$#" -eq 0 ] && set - /bin/sh -l
  
  local oldtrap="$(trap -p EXIT)"
  trap "$trapcmd" EXIT
  $root env PATH=$xpath chroot "$chroot" "$@" && rv=0 || rv=$?

  if [ -z "$oldtrap" ] ; then
    trap - EXIT
  else
    eval "$oldtrap"
  fi
  eval "$trapcmd"
  exec 9<&-
  return $rv
}

index_repo() {
  ## Create a APK repository
  ## # USAGE
  ##   index_repo [--keystore=dir] [--bind=dir] chroot
  local keystore= bindopt= bindir=
  while [ $# -gt 0 ]
  do
    case "$1" in
      --keystore=*)
	keystore="${1#--keystore=}"
	;;
      --bind=*)
	bindir="${1#--bind=}"
	;;
      *)
	break
	;;
    esac
    shift
  done
  
  local chroot="$1"  
  local chroot_arch="$(chroot_arch "$chroot")"
  [ -z "$chroot_arch" ] && die 164 "Invalid chroot directory"

  local keypath="$(find "$chroot/home" -name '*.rsa' -type f | head -1)"
  [ -z "$keypath" ] && die 194 "No keys... create HOME/.abuild"
  local keyname="$(basename "$keypath")"
  local cuser="$(basename "$(dirname "$(dirname "$keypath")")")"

  debug Saving public key $keyname to $keystore
  if [ -n "$keystore" ] ; then
    if [ -w $keystore ] ; then
      cp -a$(debug v)  $keypath.pub $keystore
    else
      $root cp -a$(debug v) $keypath.pub $keystore
    fi
  fi

  local apkindex="APKINDEX.tar.gz" rename=false
  if [ -n "$bindir" ] ; then
    [ ! -d "$bindir" ] && die 106 "$bindir: Missing directory bind"
    bindopt="-b $(readlink -f $bindir):local/$chroot_arch"
    [ ! -d "$chroot/local/$chroot_arch" ] && $root mkdir -p "$chroot/local/$chroot_arch"
    if [ -w "$bindir" ] ; then
      apkindex="APKINDEX.$$.tar.gz"
      rename=true
    fi
  else
    bindir="$chroot/local/$chroot_arch"
  fi

  local pat=
  [ $(find "$bindir" -name '*.apk' | wc -l) -gt 0 ] && pat='*.apk'

  enter_chroot $bindopt "$chroot" sh -c 'cd /local/'$chroot_arch' ; apk index -o '$apkindex' '"$pat"
  enter_chroot $bindopt "$chroot" sh -c 'cd /local/'$chroot_arch' ; abuild-sign -k /home/'$cuser'/.abuild/'$keyname' '$apkindex

  $rename && (
    cd "$bindir"
    cat "$apkindex" > APKINDEX.tar.gz
    rm -f "$apkindex"
  ) || :
}

init_chroot() {
  ## Initialize a chroot for a specific user
  ## # USAGE
  ##   init_chroot template target cuser cuid
  ## # ARGS
  ## * template -- template chroot
  ## * target -- working chroot
  ## * cuser -- chroot user
  ## * cuid -- chroot uid
  local \
    template="$1" \
    target="$2" \
    cuser="$3" \
    cuid="$4"

  [ ! -d $HOME/.abuild/ ] && die 104 "Please create an .abuild directory"
  [ ! -d "$template" ] && die 105 "Missing template: $template"
  local chroot_arch="$(chroot_arch "$template")"
  [ -z "$chroot_arch" ] && die 164 "Invalid template directory"

  [ -d "$target" ] && ( debug clean-up ; $root rm -rf "$target" )
  debug copying template
  $root cp -a "$template" "$target"
  [ -f /etc/resolv.conf ] && $root cp -L /etc/resolv.conf ${target}/etc
  
  debug initializing user
  enter_chroot "$target" adduser -D -u $cuid $cuser
  enter_chroot "$target" addgroup $cuser abuild
  $root cp -a $HOME/.abuild/ "$target/home/$cuser/.abuild"

  local dirs="src output var/cache/distfiles home/$cuser"
  local d  
  for d in $dirs
  do
    $root mkdir -p "$target/$d"
    $root chmod 777 "$target/$d"
  done
  enter_chroot "$target" chown -R $cuser:$cuser $dirs  
  
  debug setup local repository
  index_repo --keystore="$target/etc/apk/keys" "$target"

  $root tee -a "$chroot/.arm_cfg" <<-EOF
	cuser=$cuser
	cuid=$cuid
	EOF
}

tidy_build() {
  ## Builds APK in a chroot
  ## # USAGE
  ##   tidy_build chroot cuser cuid src
  ## # ARGS
  ## * chroot -- working chroot
  ## * cuser -- chroot user
  ## * cuid -- chroot uid
  ## * src -- path to source
  local apkbuild="APKBUILD"
  
  local \
    chroot="$1" \
    cuser="$2" \
    cuid="$3" \
    src="$4"
  shift 4
  
  chroot="$(readlink -f "$chroot")"
  [  ! -d "$chroot" ] && die 162 "Missing $chroot"
  local chroot_arch="$(chroot_arch "$chroot")"
  [ -z "$chroot_arch" ] && die 164 "Invalid chroot directory"
  local x_arch=$chroot_arch

  [ ! -d "$outdir" ] && die 143 "Missing outdir: $outdir"
  outdir="$(readlink -f "$outdir")"
  
  cd "$src" || die 164 "Missing source $src"

  local apkbuild=APKBUILD
  [ ! -f "$apkbuild" ] && die 109 "MISSING $apkbuild"
  apkbuild="$(readlink -f "$apkbuild")"

  local deps="$((for d in $(query_apk $apkbuild makedepends) $(query_apk $apkbuild depends)
  do
    echo $d
  done)|(sort -u))"

  debug Importing sources
  $root cp -a . "$chroot/src"
  local p \
    patchdir="$(readlink -f "../../patches")" \
    patchname="$(basename "$(readlink -f .)")"

  for p in "$patchdir/$patchname-$release.patch" "$patchdir/$patchname-$x_arch.patch" "$patchdir/$patchname.patch"
  do
    [ ! -f "$p" ] && continue
    echo "Applying patch ($(basename "$p"))..."
    $root patch -i "$p" -d "$chroot/src" -p1
  done
  
  enter_chroot "$chroot" chown -R $cuser:$cuser /src
  if [ -n "$deps" ] ; then
    debug Injecting dependencies
    enter_chroot "$chroot" apk update
    enter_chroot "$chroot" apk add $deps
  fi

  $root rm -rf "$chroot/output"
  $root mkdir -p "$chroot/output"
  $root chown $cuid:$cuid "$chroot/output"
  $root chmod 777 "$chroot/output"
  
  enter_chroot "$chroot" sudo -u $cuser sh -c 'cd /src ; abuild -P /output'
}

chroot_arch() {
  ## Checks if it is a valid chroot and display its architecture
  ## # USAGE
  ##   chroot_arch chroot
  ## # ARGS
  ## * chroot -- chroot directory to check
  ## # RETURNS
  ## 0 on success, 1 on error
  ## # OUTPUT
  ## The architecture of the chroot
  ##
  [ ! -d "$1" ] && return 1
  [ ! -f "$1"/.arm_cfg ] && return 1
  ( . "$(readlink -f "$1/.arm_cfg")" && echo "$x_arch" )
  return $?
}

setup_abuild_conf() {
  ## Create a new $HOME/.abuild
  ## # USAGE
  ##   setup_abuild_conf name email chroot_template
  local \
    name="$1" \
    email="$2" \
    chroot="$3"

  local cuser=$(id -u -n) cuid=$(id -u) wdir="$chroot-setup"
  
  debug Creating workdir
  $root cp -a "$chroot" "$wdir"
  trap "echo clean-up ; $root rm -rf $wdir" EXIT

  debug Creating signing keys
  enter_chroot "$wdir" adduser -D -u "$cuid" "$cuser"
  $root mkdir -p $wdir/home/$cuser/.abuild
  $root tee $wdir/home/$cuser/.abuild/abuild.conf <<-EOF
	PACKAGER="$name <$email>"
	MAINTAINER="$(echo '$PACKAGER')"
	EOF
  $root chown -R $cuid:$cuid $wdir/home/$cuser/.abuild
  enter_chroot "$wdir" sudo -u "$cuser" abuild-keygen -n
  tee -a $wdir/home/$cuser/.abuild/abuild.conf <<-EOF
	PACKAGER_PRIVKEY="$(echo '$HOME/.abuild/')$(find $wdir/home/$cuser/.abuild -name '*.rsa' -printf '%f')"
	EOF
  debug creating HOME/.abuild
  cp -a $wdir/home/$cuser/.abuild $HOME/.abuild
}

run_abuild() {
  ## Run abuild in a chroot
  ## # USAGE
  ##   run_abuild chroot wdir cuser cuid outdir init src
  local \
    chroot="$1" \
    wdir="$2" \
    cuser="$3" \
    cuid="$4" \
    outdir="$5" \
    init="$6" \
    src="$7"

  local chroot_arch="$(chroot_arch "$chroot")"
  [ -z "$chroot_arch" ] && die 164 "Invalid template directory"

  if [ ! -d "$wdir" ] ; then
    $init || echo "Working chroot missing, initializing"
    init=true
  fi
  $init && init_chroot "$chroot" "$wdir" "$cuser" "$cuid"
  tidy_build "$wdir" "$cuser" "$cuid" "$src"  || return 1

  local apks="$(find "$wdir/output" -name '*.apk')"
  if [ $(echo "$apks" | wc -l) -eq 0 ] ; then
    echo "$src: No APK's found!"
    return 1
  fi

  echo "$apks" | while read l
  do
    apk=$(basename "$l")
    cp -a "$l" "$outdir/$apk"
    for q in $chroot $wdir
    do
      [ ! -d "$q/local/$chroot_arch" ] && $root mkdir "$q/local/$chroot_arch"
      $root cp -a "$l" "$q/local/$chroot_arch/$apk"
    done
  done
  index_repo "$wdir"
}

sysupd() {
  local chroot="$(readlink -f "$1" )"
  [ ! -d "$chroot" ] && die 121 "Missing $1 chroot"
  shift

  [ -f /etc/resolv.conf ] && $root cp -L /etc/resolv.conf ${chroot}/etc
  enter_chroot "$chroot" apk update
  enter_chroot "$chroot" apk upgrade
}

depsort() {
  local f

  (
    if [ $# -eq 0 ] ; then
      cat
    else
      find "$@" -name APKBUILD
    fi
  ) | (
    local x_arch=$(basearch)
    while read f
    do
      [ -d "$f" ] && f="$f/APKBUILD"
      [ x"$(basename "$f")" != x"APKBUILD" ] && continue

      d=$(dirname "$f")

      (
	eval "$(query_apk "$f" pkgname subpackages depends makedepends)"
	#x="$(query_apk "$f" pkgname subpackages depends makedepends)"
	#set -x
	#eval "$x"

	echo "$pkgname $d"
	for s in $subpackages
	do
	  echo "$pkgname $s"
	done
	for s in $depends $makedepends
	do
	  echo "$s $pkgname"
	done
      )
    done
  ) | tsort | (
    while read d
    do
      [ -d "$d" ] && echo "$d"
    done
  )
}

check_envs() {
  local x a b v
  for x in "$@"
  do
    a=$(echo $x | cut -d: -f1)
    b=$(echo $x | cut -d: -f2)

    eval 'v="${'"$a"':-}"'
    [ -z "$v" ] && continue
    eval ${b}'="$v"'
  done
}

template_chroot() {
  echo "$scratch_dir"/chroot-"$release"-"$x_arch"
}
user_chroot() {
  echo "$scratch_dir"/chroot-"$release"-"$x_arch"-"$(id -u -n)"
}

##################################################################
# Globals
##################################################################

wget="wget -q"
xpath=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
scratch_dir=/var/lib/arm_chroots

if [ $(id -u) -eq 0 ] ; then
  root=""
else
  root=sudo
  type $root >/dev/null || die 136 "This program requires sudo to be installed"
fi
cleanup=:
type declare >/dev/null || die 99 "Unsupported shell"


if [ -f $HOME/.arm_prefs ] ; then
 . $HOME/.arm_prefs
else
  echo "Creating default configuration file"
  tee $HOME/.arm_prefs <<-EOF
	# Default mirror site URL
	#mirror=http://nl.alpinelinux.org/alpine/
	# Default release
	#release=x.y
	#
	# You can usually leave these alone...
	#
	# Directory where to store all CHROOTS
	#scratch_dir=/var/lib/arm_chroots
	# Default arch (auto-detected)
	#x_arch=$(basearch)
	# Default path to set in the chroot environment
	#xpath=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
	# wget command
	#wget="wget -q"
	EOF
fi
check_envs \
  ARM_MIRROR:mirror \
  ARM_CHROOTS:scratch_dir \
  ARM_RELEASE:release \
  ARM_ARCH:x_arch

##################################################################
# Command line overrides
##################################################################
while [ $# -gt 0 ]
do
  case "$1" in
    --mirror=*)
      mirror=${1#--mirror=}
      ;;
    --scratch-dir=*)
      scratch_dir=${1#--scratch-dir=}
      ;;
    --release=*)
      release=${1#--release=}
      ;;
    --arch=*)
      x_arch=${1#--arch=}
      ;;
    *)
      break
      ;;
  esac
  shift
done

[ -z "${x_arch:-}" ] && x_arch="$(basearch)"
if [ -n "${scratch_dir:-}" ] ; then
  [ ! -d "$scratch_dir" ] && $root mkdir -p "$scratch_dir"
  scratch_dir="$(readlink -f "$scratch_dir" |sed -e 's!/*$!!')"
fi
[ -n "${mirror:-}" ] && mirror="$(echo "$mirror" | sed -e 's!/*$!!')"

##################################################################
# User visible commands
##################################################################
op_create() {
  local chroot="$(template_chroot)"

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ -d "$chroot" ] && die 46 "$chroot: template chroot already exists"
  [ $# -ne 0 ] && die 132 "Usage: $0 create [--chroot=x]"
  create_chroot "$mirror" "$release" "$x_arch" "$chroot"
}

op_nuke() {
  local chroot="$(template_chroot)"

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      *)
	break
	;;
    esac
    shift
  done

  local dirname="$(dirname "$chroot")"
  local basename="$(basename "$chroot")"

  find "$dirname" -mindepth 1 -maxdepth 1 -name "$basename"'*' -type d | (
    while read ldir
    do
      [ ! -f "$ldir/.arm_cfg" ] && continue
      debug nuking $ldir
      $root rm -rf "$ldir"
    done
  )
}

op_keygen() {
  local chroot="$(template_chroot)"

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --name=*)
	local name="${1#--name=}"
	;;
      --email=*)
	local email="${1#--email=}"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ $(id -u) -eq 0 ] && die 169 "Do not run this as root"
  [ -d $HOME/.abuild ] && die 149 "HOME/.abuild already exists"

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing template chroot"
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"
  
  echo "name=$name"
  echo "email=$email"
  echo "chroot=$chroot"

  setup_abuild_conf "$name" "$email" "$chroot"
}

op_apkindex() {
  local keystore= \
    chroot="$(template_chroot)"
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --keystore=*)
	local keystore="$1"
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ $# -ne 1 ] && die 81 "Usage: $0 apkindex [--keystore=x] [--chroot=y] repodir"
  local bindir="$1"
  [ ! -d "$bindir" ] && die 80 "$bindir: Missing repo path"

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing template chroot"
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"

  local cuser="$(id -u -n)" cuid="$(id -u)"
  init_chroot "$chroot" "$chroot-$cuser" "$cuser" "$cuid"
  index_repo $keystore --bind="$bindir" "$chroot-$cuser"
}

op_enter() {
  local \
    chroot=$(user_chroot) \
    usermode=true \
    init=false \
    binds=
  
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --bind=*|-b?*)
	binds="$binds $1"
	;;
      -b)
	binds="$binds -b $2"
	shift
	;;
      --init)
	init=true
	;;
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	usermode=false
	;;
      --user|-u)
	chroot=$(user_chroot)
	usermode=true
	;;
      --root|-r)
	chroot=$(user_chroot)
	usermode=false
	;;
      --template|-t)
	chroot=$(template_chroot)
	usermode=false
	;;
      *)
	break
	;;
    esac
    shift
  done

  if [ ! -d "$chroot" ] ; then
    $init || die 47 "$chroot: Missing chroot"
    [ "$chroot" = $(template_chroot) ] && die 106 "$chroot: Missing template chroot"
    if [ $(id -u) -eq 0 ] ; then
      local cuser='user' cuid='1001'
    else
      local cuser="$(id -u -n)" cuid="$(id -u)"
    fi
    init_chroot "$(template_chroot)" "$chroot" "$cuser" "$cuid"
  fi
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"

  [ $# -eq 0 ] && set - sh -l

  if $usermode ; then
    local cuser="$(query_apk "$chroot/.arm_cfg" cuser)"
    [ -z "$cuser" ] && die 118 "Unable to set-up user mode"
    enter_chroot $binds "$chroot" sudo -u "$cuser" "$@"
  else
    enter_chroot $binds "$chroot" "$@"
  fi
}

op_upgrade() {
  local chroot=$(template_chroot)
  
  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --user)
	chroot=$(user_chroot)
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing chroot"
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"
  sysupd "$chroot"
}

op_ccm() {
  local chroot=$(template_chroot) op="$1" ; shift

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --user)
	chroot=$(user_chroot)
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing chroot"
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"
  local chroot_arch="$(. $chroot/.arm_cfg && echo $x_arch)"
  [ -z "$chroot_arch" ] &&  die 48 "$chroot: Error reading chroot"

  case "$op" in
    list|l)
      echo "$chroot_arch:"
      ls "$@" "$chroot/local/$chroot_arch"
      ;;
    inject|i)
      local apk
      for apk in "$@"
      do
	$root cp $(debug -v) "$apk" "$chroot/local/$chroot_arch"
      done
      ;;
    delete|d)
      find "$chroot/local/$chroot_arch" -maxdepth 1 -mindepth 1 | while read l
      do
        $root rm -rf "$l"
      done
      ;;
    *)
      die 50 "Internal error!"
  esac
}

op_build() {
  if [ $(id -u) -eq 0 ] ; then
    local cuser='user' cuid='1001'
  else
    local cuser="$(id -u -n)" cuid="$(id -u)"
  fi

  local chroot="$(template_chroot)" wdir="$(user_chroot)"
  local init=true outdir=

  while [ "$#" -gt 0 ] ; do
    case "$1" in
      --chroot=*)
	chroot="$(readlink -f "${1#--chroot=}"  | sed -e 's!/*$!!')"
	;;
      --wdir=*)
	wdir="$(readlink -f "${1#--wdir=}" | sed -e 's!/*$!!')"
	;;
      --cuser=*)
	local cuser=${1#--cuser=}
	;;
      --cuid=*)
	local cuid=${1#--cuid=}
	;;
      --output=*)
	outdir="$(readlink -f "${1#--output=}"  | sed -e 's!/*$!!')"
	;;
      --no-init)
	init=false
	;;
      *)
	break
	;;
    esac
    shift
  done

  [ ! -d "$chroot" ] && die 47 "$chroot: Missing template chroot"
  [ ! -f "$chroot/.arm_cfg" ] &&  die 48 "$chroot: Invalid chroot"

  [ $# -eq 0 ] && set - .

  local src rv=0
  
  for src in "$@"
  do
    ( run_abuild "$chroot" "$wdir" "$cuser" "$cuid" "$outdir" $init "$src" ) && continue
    rv=$(expr $rv + 1)
  done
  return $rv
}


op_repo() {
  op="$1" ; shift
  [ $# -lt 1 ] && die 129 "Usage: $0 $op chroot [apks]"
  local chroot="$(readlink -f "$1" )"
  [ ! -d "$chroot" ] && die 121 "Missing $1 chroot"
  shift
  local chroot_arch="$(. $chroot/.arm_cfg && echo $x_arch)"
  local apk repodir="$chroot/local/$chroot_arch"
  [ ! -d "$repodir" ] && die 137 "Missing repo dir"

  case "$op" in
    l)
      ls "$@" "$repodir"
      ;;
    i)
      for apk in "$@"
      do
        $root cp -a$(debug v) "$apk" "$repodir"
      done
      ;;
    p)
      echo "$repodir"
      ;;
  esac
  
}

##################################################################
# Main
##################################################################

[ $# -eq 0 ] && usage "$0"

op="$1" ; shift
case "$op" in
  c|create|mkchroot)
    op_create "$@"
    ;;
  e|enter)
    op_enter "$@"
    ;;
  keygen)
    op_keygen "$@"
    ;;
  b|build)
    op_build "$@"
    ;;  
  apkindex)
    op_apkindex "$@"
    ;;
  depsort)
    depsort "$@"
    ;;
  u|upgrade)
    op_upgrade "$@"
    ;;
  h|help)
    manual "$0"
    ;;
  n|nuke)
    op_nuke "$@"
    ;;
  l|list|i|inject|d|delete)
    op_ccm "$op" "$@"
    ;;
  *)
    die 228 "Invalid op $op. Use help"
    ;;
esac


