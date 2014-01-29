#!/bin/bash

# open file and read line

# check_daemon script to use
CHECK_DAEMON=check_daemon.pl
NAGIOS_PLUGIN_DIR=/usr/lib/nagios/plugins
SERVICE_DESCRIPTION="Originated by siconf.py"

# declare associative array
declare -A service_array
declare -A service_on_host
### usage
function Usage()
{
	cat <<__EOF__>&2

Usage: $0 map 

__EOF__

}

### parse
function parse() {
 #set -x
 line=$@
 # test if line starts with # or is an empty line
 test ${line:0:1}x == "#x" -o "${line}x" == "x" && return 1
# echo $line
 
 # is a service definition
 if echo $line | grep "=" -q
 then
 	key=`echo $line | cut -d"=" -f1`
 	value=`echo $line | cut -d"=" -f2` 	 	
 	service_array[$key]=$value
 # is a `host has this service` definition
 else
	host=`has_VIP $1`
	# if already exists a host as a key
	if [ ${service_on_host[$host]+_} ]
	then
		# take previous values and add them to current
		prev_values=${service_on_host[$host]}
		new_values="$2,$prev_values"
		service_on_host[$host]=$new_values				
	else
		# there is no host as a key in the array
		service_on_host[$host]=$2		
	fi
 fi

}

### has_VIP
function has_VIP() {
	split_vip=(`echo $@ | tr "|" " "`)
	if [ ${#split_vip[@]} -gt 1 ]
	then
		who_has_VIP ${split_vip[@]}
	else
		echo $split_vip
	fi
}

### who_has_VIP
function who_has_VIP() {
	my_IPs=($@)
	echo ${my_IPs[1]}
}

###
function which_port() {
	split_socket=(`echo $@ | tr ":" " "`)
	bind_to_ip=${split_socket[0]}
	proto=${split_socket[1]:0:3}	
	port=${split_socket[1]:3:5}
	echo $port/$proto
}

###
function parse_service() {
 daemon=$1
 instances="-n $2"
 test $3x != x && port="-p `which_port $3`" || port=""
 test $4x != x && log_file="-l $4" || log_file=""
 test $5x != x && mtime="-F $5" || mtime=""
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
	if [ $? -gt 0 ]
	then
		continue
	fi
done < $MAP_FILE


# iterate over keys of host array
for host in ${!service_on_host[@]}
do
	# how many services on that host?
	services=${service_on_host[$host]}
	# split services
	split_services=(`echo $services | tr "," " "`)
	# for each service on that host
	for serv in ${split_services[@]}
	do
		# i have the host
		# i have the service on that host
		parse_service ${service_array[$serv]}
		check_command="$host|||$NAGIOS_PLUGIN_DIR/$CHECK_DAEMON \
		$daemon $instances \
		$port \
		$log_file $mtime \
		|$SERVICE_DESCRIPTION"
		echo $check_command		
#		echo "$host|||${service_array[$serv]}|check_daemon script"
	done
done

#echo ${split_services[@]}

exit 0

echo SERVICE ARRAY
echo "keys are:"
echo -e "--------" ${!service_array[@]}

echo "values are:"
echo -e "--------" ${service_array[@]}

echo HOST ARRAY
echo "keys are:"
echo -e "--------" ${!service_on_host[@]}

echo "values are:"
echo -e "--------" ${service_on_host[@]}
# target:frequency:option:command:service_description
# host1,host3,host4:20m::dummy_check:a dummy check
echo "######################"

