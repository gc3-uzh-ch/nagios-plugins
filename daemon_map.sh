#!/bin/bash

# open file and read line

# check_daemon script to use
CHECK_DAEMON=check_daemon.pl

### usage
function Usage()
{
	cat <<__EOF__>&2

Usage: $0 map 

__EOF__

}

### parse
function parse() {
 host=`has_VIP $1`
 daemon=$2
 ip_socket=$3 
}

### has_VIP
function has_VIP() {
	cut_vip=(`echo $@ | tr "|" " "`)
	if [ ${#cut_vip[@]} -gt 1 ]
	then
		who_has_VIP ${cut_vip[@]}
	else
		echo $cut_vip
	fi
}

### who_has_VIP
function who_has_VIP() {
	my_IPs=($@)
	echo ${my_IPs[1]}
}


### main
if [ $# -ne 1 ]
then
	Usage
	exit 1
fi

MAP_FILE=$1

while read line
do
	parse $line
	echo $host::$CHECK_DAEMON $daemon
done < $MAP_FILE

# target:frequency:option:command:service_description
# host1,host3,host4:20m::dummy_check:a dummy check


exit 0

