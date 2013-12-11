#!/bin/bash

# baro - 2013-11-11 #

      OK=0	# all is fine, thanks for asking
 WARNING=1	# something's wrong, but it's not that bad, though
CRITICAL=2	# it's pretty bad, FUBAR & FUD
 UNKNOWN=3	# wtf? RTFM

   SYSFS=/sys/class/infiniband/

function OK()
{
#	echo $FUNCNAME
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
function Usage()
{
	cat <<__EOF__>&2

Usage: $0 [--card CARD] [--port PORT] [--sysfs SYSFS] [--logical-only|--physical-only]
       $0 [--interface INTERFACE]     [--sysfs SYSFS] [--logical-only|--physical-only]

	CARD		qib0, mthca0, mlx4_0, ...
	PORT		1, 2, ...
	SYSFS		$SYSFS

	INTERFACE	ib0, ib1, ...

__EOF__
	exit $UNKNOWN
}

function card_from_interface()
{
	pgid="$(/sbin/ip link show $1 | awk '/link/{print $2}' | sed -r 's/://g;s/^.+(.{16}$)/\1/;s/..../&:/g;s/:$//;')"
	test "x$pgid" != "x" || UNKNOWN

	path="$(grep -l $pgid$ /sys/class/net/$1/device/infiniband/*/ports/*/gids/*)"
	test "x$path" != "x" || UNKNOWN

#	echo $path | cut -d/ -f 8,10 --output-delimiter=' '
	CARD=$(echo $path | cut -d/ -f 8)
	PORT=$(echo $path | cut -d/ -f 10)
}

LONLY=false
PONLY=false

while [ $# -gt 0 ]
do
	case $1 in
		-x) set -x ;;
		-s|--sysfs)		SYSFS=$2	; shift ;;
		-c|--card)		CARD=$2		; shift ;;
		-p|--port)		PORT=$2		; shift ;;
		-L|--logical-only)	LONLY=true	;;
		-P|--physical-only)	PONLY=true	;;
		-i|--interface)		card_from_interface $2 ; shift ;;
		*) Usage ;;
	esac
	shift
done

        ok=0	# 0 = not ok, >0 ok
     cards=0	# how many cards do we have?
     ports=0	# how many ports? (total)
        ps=0	# n of physical states checked (in order to be OK: $ps == $ls == $ok, warning or critical otherwise)
        ls=0	# n of logical states checked (in order to be OK: $ps == $ls == $ok, warning or critical otherwise)
      warn=0	# n of check leading to warnings
      crit=0	# n of check indicating a critical situation
 unhandled=0	# something we don't care or we don't know how to handle

for card in $SYSFS/*/
do
	card=${card%/}
	c=${card##*/}
	if [ "x$CARD" != "x" ]
	then
		test "x$c" = "x$CARD" || continue
	fi
	let cards++

	for port in $card/ports/*/
	do
		port=${port//\/\//\/}
		port=${port%/}
		p=${port##*/}

		if [ "x$PORT" != "x" ]
		then
			test "x$p" = "x$PORT" || continue
		fi
		let ports++

		if ! $LONLY
		then
			phys_state=$port/phys_state
			if [ -e $phys_state ]
			then
				let ps++
				read num phys < $phys_state
				echo >&2 "$c/$p: $num $phys"
				case $phys in
					LinkUp)		let ok++	;; # ok
					Polling)	let warn++	;; # no link
					Disabled)	let crit++	;; # port disabled or driver problem
					*)		let unhandled++	;; # not OK, temporary error, unknown state
				esac
			fi
		fi

		if ! $PONLY
		then
			state=$port/state
			if [ -e $state ]
			then
				let ls++
				read num logic < $state
				echo >&2 "$c/$p: $num $logic"
				case $logic in
					ACTIVE)		let ok++	;; # ok
					INIT)		let warn++	;; # no SM
					DOWN)		let crit++	;; # phys_state != LinkUp
					*)		let unhandled++	;; # not OK, temporary error, unknown state
				esac
			fi
		fi
	done
done

test $crit      -gt 0 && CRITICAL
test $warn      -gt 0 && WARNING
test $unhandled -gt 0 && WARNING
test $ok -gt 0 -a $ok -ge $((ls+ps)) && OK

if [ $cards -eq 0 ]
then
	echo >&2 "*** no suitable cards found"
	UNKNOWN
fi
if [ $ports -eq 0 ]
then
	echo >&2 "*** no suitable ports found"
	UNKNOWN
fi
test ! $PONLY -a $ls -eq 0 && echo >&2 "*** no logical links checked"
test ! $LONLY -a $ps -eq 0 && echo >&2 "*** no physical links checked"
UNKNOWN


# ofed/src/ofa_kernel-1.5.4.1/drivers/infiniband/core/sysfs.c
# 
#      86 static ssize_t state_show(struct ib_port *p, struct port_attribute *unused,
#      87                           char *buf)
#      88 {
#      89         struct ib_port_attr attr;
#      90         ssize_t ret;
#      91 
#      92         static const char *state_name[] = {
#      93                 [IB_PORT_NOP]           = "NOP",
#      94                 [IB_PORT_DOWN]          = "DOWN",
#      95                 [IB_PORT_INIT]          = "INIT",
#      96                 [IB_PORT_ARMED]         = "ARMED",
#      97                 [IB_PORT_ACTIVE]        = "ACTIVE",
#      98                 [IB_PORT_ACTIVE_DEFER]  = "ACTIVE_DEFER"
#      99         };
#     100 
#     101         ret = ib_query_port(p->ibdev, p->port_num, &attr);
#     102         if (ret)
#     103                 return ret;
#     104 
#     105         return sprintf(buf, "%d: %s\n", attr.state,
#     106                        attr.state >= 0 && attr.state < ARRAY_SIZE(state_name) ?
#     107                        state_name[attr.state] : "UNKNOWN");
#     108 }
# 
# 
#     202 static ssize_t phys_state_show(struct ib_port *p, struct port_attribute *unused,
#     203                                char *buf)
#     204 {
#     205         struct ib_port_attr attr;
#     206 
#     207         ssize_t ret;
#     208 
#     209         ret = ib_query_port(p->ibdev, p->port_num, &attr);
#     210         if (ret)
#     211                 return ret;
#     212 
#     213         switch (attr.phys_state) {
#     214         case 1:  return sprintf(buf, "1: Sleep\n");
#     215         case 2:  return sprintf(buf, "2: Polling\n");
#     216         case 3:  return sprintf(buf, "3: Disabled\n");
#     217         case 4:  return sprintf(buf, "4: PortConfigurationTraining\n");
#     218         case 5:  return sprintf(buf, "5: LinkUp\n");
#     219         case 6:  return sprintf(buf, "6: LinkErrorRecovery\n");
#     220         case 7:  return sprintf(buf, "7: Phy Test\n");
#     221         default: return sprintf(buf, "%d: <unknown>\n", attr.phys_state);
#     222         }
#     223 }

#EOF
