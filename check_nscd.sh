#!/bin/bash
#
# task description in https://ocikbgs.uzh.ch/adminwiki/tasks/Icinga_check_user/
# check existence of well-known users from LDAP, restart nscd as necessary

# icinga return values
# set -x

      OK=0	# all is fine, thanks for asking
 WARNING=1	# something's wrong, but it's not that bad, though
CRITICAL=2	# it's pretty bad, FUBAR & FUD
 UNKNOWN=3	# wtf? RTFM

function OK()
{
	echo $FUNCNAME
	exit $OK
}
function WARNING()
{
	echo $FUNCNAME
	exit $WARNING
}
function CRITICAL()
{
	echo $FUNCNAME
	exit $CRITICAL
}
function UNHANDLED()
{
	echo $FUNCNAME
	CRITICAL "$@"
}
function UNKNOWN()
{
	echo $FUNCNAME
	exit $UNKNOWN
}

RESTART_NSCD=false

CHECK_COMMAND="getent passwd"
#CHECK_COMMAND="id"

function Usage()
{
	cat <<__EOF__>&2

Usage: $0 [-u user1[,user2,user3,...] | -f /path/to/filename] 

	check_nscd -u riccardo,antonio
	check_nscd -f /pathname

__EOF__
	UNKNOWN
}

function check_user_existence() {
	users_array=( "${@}" )
	for user in "${users_array[@]}"
	do	
#		test=`$CHECK_COMMAND $user 2> /dev/null`
		test=`$CHECK_COMMAND $user`		
		if [ "x$test" == "x" ]
		then
			RESTART_NSCD=true
		fi
	done	
}

if [ $# -ne 2 ]
then
	Usage
fi

case $1 in
	-f|--check-file) FILENAME=$2 ;;
	-u|--users) USERS_CMDLINE=( `echo $2 | tr "," " "` ) ;;
	*) Usage ;;
esac

# checks on filename and check user existence
if [ "x$FILENAME" != "x" ]
then
	# check file existence
	test -f $FILENAME || UNKNOWN

	# file must have one column only
	how_many_columns=`awk '{print NF}' $FILENAME  | sort -r | head -1`
	test $how_many_columns -eq 1 || UNKNOWN

	# file must have valid username, 3-31 chars in length
	egrep -v '^(#.*|[a-zA-Z0-9_-]+)$' $FILENAME | grep -q . && UNKNOWN

	# read users from file and put them into an array, then check users existence
	USERS_FROM_FILE=( $(egrep '^[a-zA-Z0-9_-]+$' $FILENAME) )
	check_user_existence "${USERS_FROM_FILE[@]}"		
fi

# check on users provided on command line and check existence
if [ "x$USERS_CMDLINE" != "x" ]
then
	for user in "${USERS_CMDLINE[@]}"
	do
		invalid_user=`echo $user | egrep -v '^[a-zA-Z0-9_-]+$'`
		test "x$invalid_user" == 'x' || UNKNOWN
	done
	check_user_existence "${USERS_CMDLINE[@]}"
fi

# restart service if true and exit if restart fails
if $RESTART_NSCD
then
	/etc/init.d/nscd restart 2> /dev/null
	test $? == 0 || CRITICAL 
fi

RESTART_NSCD=false

if [ "x$FILENAME" != "x" ]
then
	check_user_existence "${USERS_FROM_FILE[@]}"
else
	check_user_existence "${USERS_CMDLINE[@]}"
fi

if $RESTART_NSCD
then
	CRITICAL
fi
OK