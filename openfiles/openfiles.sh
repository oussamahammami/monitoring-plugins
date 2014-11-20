#!/bin/bash

ASTFILES=/tmp/astfiles
ASTPORTS=/tmp/astports
RTPFILES=/tmp/rtpfiles
RTPFILES2=/tmp/rtpfiles2

print_description() {
	echo ".0"
	echo STRING
	echo "Openfiles Counter $1 $2 $3"
}

print_asterisk() {
	echo ".1"
	echo integer
	if [ -r $ASTFILES ] ; then
		cat $ASTFILES
	else
		echo 0
	fi
}

print_rtpproxy() {
	echo ".2"
	echo integer
	if [ -r $RTPFILES ] ; then
		cat $RTPFILES
	else
		echo 0
	fi
}

print_astports() {
	echo ".3"
	echo integer
	if [ -r $ASTPORTS ] ; then
		cat $ASTPORTS
	else
		echo 0
	fi
}

print_rtpproxy2() {
	echo ".4"
	echo integer
	if [ -r $RTPFILES2 ] ; then
		cat $RTPFILES2
	else
		echo 0
	fi
}

case ${3} in
	"${1}")
			if [ ${2} = "-n" ] ; then
				echo -n ${1}
				print_description
			fi
			;;

	"${1}.0")	
			echo -n ${1}
			if [ ${2} = "-n" ] ; then
				print_asterisk
			elif [ ${2} = "-g" ] ; then
				print_description
			fi
			;;
	"${1}.1")
			echo -n ${1}
			if [ ${2} = "-n" ] ; then
				print_rtpproxy
			elif [ ${2} = "-g" ] ; then
				print_asterisk
			fi
			;;
	"${1}.2")
			echo -n ${1}
			if [ ${2} = "-n" ] ; then
				print_astports
			elif [ ${2} = "-g" ] ; then
				print_rtpproxy
			fi
			;;
	"${1}.3")
			echo -n ${1}
			if [ ${2} = "-n" ] ; then
				print_rtpproxy2
			elif [ ${2} = "-g" ] ; then
				print_astports
			fi
			;;
	"${1}.4")
			if [ ${2} = "-g" ] ; then
				echo -n ${1}
				print_rtpproxy2
			fi
			;;
	*)		
			echo -n $1
			print_description
			;;
esac

