#!/bin/sh
#
#
# A simple "hello world" Nagios/Icinga check, to be used as a
# template for writing other and more complex ones.
#

me="$(basename $0)"

usage () {
cat <<EOF
Usage: $me [options]

A short description of what this check does should be here,
but it is not (yet).

Options:

  --message, -m  TEXT
                Exit with OK status and use TEXT as check result message.

  --help, -h     Print this help text.

EOF
}


## exit statuses recognized by Nagios
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3


## helper functions
die () {
  rc="$1"
  shift
  (echo -n "$me: ERROR: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
  exit $rc
}

warn () {
  (echo -n "$me: WARNING: ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi) 1>&2
}

have_command () {
  type "$1" >/dev/null 2>/dev/null
}

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}


## parse command-line

short_opts='hm:'
long_opts='message:,help'

if [ "x$(getopt -T)" != 'x--' ]; then
    # GNU getopt
    args=$(getopt --name "$me" --shell sh -l "$long_opts" -o "$short_opts" -- "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    # use 'eval' to remove getopt quoting
    eval set -- $args
else
    # old-style getopt, use compatibility syntax
    args=$(getopt "$short_opts" "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    set -- $args
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --message|-m) message="$2"; shift ;;
        --help|-h)    usage; exit 0 ;;
        --)           shift; break ;;
    esac
    shift
done


## main

# RETURN OUTPUT TO NAGIOS
# using the example `-m` parameter parsed from commandline
echo "OK - ${message}"
exit $OK
